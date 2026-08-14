/*
    03_tables.sql
    Tablas de la capa de staging.

    Se ejecuta UNA sola vez.
*/

USE WWI_Staging;
GO

/* ---------------------------------------------------------------------------
   Sales.Orders — copia espejada de WideWorldImporters.Sales.Orders

   Todas las columnas del origen son NULL-ables aca, aunque en produccion varias
   sean NOT NULL. El trabajo de staging es capturar lo que venga, incluso si viene
   mal; la validacion es un paso posterior (etl.usp_ValidateSalesOrders). Si la
   tabla rechazara filas con constraints, se estaria validando en la capa
   equivocada y se perderia visibilidad de que llego mal.

   Comments / DeliveryInstructions / InternalComments son NVARCHAR(MAX) porque asi
   son en el origen. CustomerPurchaseOrderNumber es NVARCHAR(20), igual que el origen.

   LoadBatchId + LoadedAt son columnas de auditoria propias de staging: permiten
   saber que corrida trajo cada fila y cuando. No existen en el origen.
--------------------------------------------------------------------------- */
CREATE TABLE Sales.Orders (
    OrderID                     INT              NULL,
    CustomerID                  INT              NULL,
    SalespersonPersonID         INT              NULL,
    PickedByPersonID            INT              NULL,
    ContactPersonID             INT              NULL,
    BackorderOrderID            INT              NULL,
    OrderDate                   DATE             NULL,
    ExpectedDeliveryDate        DATE             NULL,
    CustomerPurchaseOrderNumber NVARCHAR(20)     NULL,
    IsUndersupplyBackordered    BIT              NULL,
    Comments                    NVARCHAR(MAX)    NULL,
    DeliveryInstructions        NVARCHAR(MAX)    NULL,
    InternalComments            NVARCHAR(MAX)    NULL,
    PickingCompletedWhen        DATETIME2        NULL,
    LastEditedBy                INT              NULL,
    LastEditedWhen              DATETIME2        NULL,
    LoadBatchId                 UNIQUEIDENTIFIER NOT NULL,
    LoadedAt                    DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---------------------------------------------------------------------------
   Sales.OrderLines — copia espejada de WideWorldImporters.Sales.OrderLines

   Mismo criterio que Sales.Orders: todo NULL-able, sin constraints, sin indices.
   Staging captura lo que venga; validar es un paso posterior.

   UnitPrice es NULL-able TAMBIEN en el origen — es la unica medida monetaria del
   modelo y la fuente admite que falte. Un NULL aca no rompe nada: se propaga por
   la multiplicacion (Quantity * NULL = NULL) y despues SUM lo ignora en silencio,
   asi que el total sale mas chico sin ningun error. Por eso se valida aparte, y
   por eso la capa resumen no puede aceptar NULL en una medida.

   Description NO es una descripcion de la linea: es el nombre del producto
   congelado al momento del pedido. El origen lo desnormaliza a proposito para que
   un renombre posterior no altere pedidos historicos. Hoy coincide con
   Warehouse.StockItems.StockItemName en las 231.412 filas — porque todavia no
   renombraron nada, no porque la columna sobre.

   Quantity es lo pedido; PickedQuantity es lo efectivamente despachado.
--------------------------------------------------------------------------- */

CREATE TABLE Sales.OrderLines (
	OrderLineID					INT              NULL,
	OrderID						INT              NULL,
	StockItemID					INT              NULL,
	Description					NVARCHAR(100)    NULL,
	PackageTypeID				INT              NULL,
	Quantity					INT              NULL,
	UnitPrice					DECIMAL(18,2)    NULL,
	TaxRate						DECIMAL(18,3)    NULL,
	PickedQuantity				INT              NULL,
	PickingCompletedWhen		DATETIME2		 NULL,
	LastEditedBy				INT              NULL,
	LastEditedWhen				DATETIME2        NULL,
	LoadBatchId                 UNIQUEIDENTIFIER NOT NULL,
	LoadedAt                    DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---------------------------------------------------------------------------
   etl.ValidationLog — problemas de calidad detectados, por corrida

   Generica para toda la capa: SchemaName + TableName identifican que tabla se
   valido, asi una sola tabla sirve para todo el pipeline.

   RuleName y AffectedRowCount van separados (en vez de un unico texto tipo
   "5 filas con X nulo") para poder filtrar y agrupar sin parsear strings.

   Tiene identity propio porque puede haber VARIAS filas por batch, una por regla.
--------------------------------------------------------------------------- */
CREATE TABLE etl.ValidationLog (
    ValidationLogID  INT              IDENTITY(1,1) PRIMARY KEY,
    LoadBatchId      UNIQUEIDENTIFIER NOT NULL,
    SchemaName       NVARCHAR(128)    NOT NULL,
    TableName        NVARCHAR(128)    NOT NULL,
    RuleName         NVARCHAR(128)    NOT NULL,
    AffectedRowCount INT              NOT NULL,
    LoadedAt         DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---------------------------------------------------------------------------
   etl.LoadBatch — una fila por ejecucion del pipeline (control table)

   La fila se inserta al ARRANCAR con Status = 'Running' y se actualiza al
   terminar. Si se escribiera solo al final, las corridas que fallan no dejarian
   ningun rastro — que es justamente el problema que esta tabla resuelve.

   LoadBatchId es la PK: hay exactamente una fila por corrida, y declararlo asi
   impide que el pipeline registre dos filas para el mismo batch.

   StartedAt lleva DEFAULT porque su valor se conoce al insertar.
   EndedAt NO lleva default: si lo tuviera, cada fila naceria "terminada" y
   WHERE EndedAt IS NULL nunca encontraria las corridas en curso o colgadas.

   ErrorMessage es NVARCHAR(4000) porque ERROR_MESSAGE() devuelve exactamente ese tipo.

   El CHECK sobre Status es apropiado aca (a diferencia de las tablas espejadas):
   estos datos los genera codigo propio, asi que el constraint no rechaza realidad
   ajena — atrapa bugs propios, como un typo 'Suceeded'.
--------------------------------------------------------------------------- */
CREATE TABLE etl.LoadBatch (
    LoadBatchId  UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    SchemaName   NVARCHAR(128)    NOT NULL,
    TableName    NVARCHAR(128)    NOT NULL,
    StartedAt    DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    EndedAt      DATETIME2        NULL,
    Status       NVARCHAR(20)     NOT NULL
        CONSTRAINT CK_LoadBatch_Status CHECK (Status IN (N'Running', N'Succeeded', N'Failed')),
    RowsLoaded   INT              NULL,
    ErrorNumber  INT              NULL,
    ErrorMessage NVARCHAR(4000)   NULL
);
GO
