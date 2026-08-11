/*
    05_usp_LoadSalesOrders.sql
    Extraccion de WideWorldImporters.Sales.Orders hacia la capa de staging.

    Re-ejecutable (CREATE OR ALTER). Depende de etl.usp_ValidateSalesOrders,
    por eso ese script lleva un numero anterior.

    Carga completa (full load) e idempotente: TRUNCATE + INSERT. Correrlo N veces
    siempre deja el snapshot actual del origen, sin acumular duplicados.

    La transaccion envuelve SOLO el TRUNCATE + INSERT. Sin ella, TRUNCATE se
    confirmaria por su cuenta y un fallo del INSERT dejaria la tabla vacia. Con ella,
    un fallo revierte ambos y sobreviven los datos de la carga anterior — en BI casi
    siempre es preferible mostrar datos de ayer completos que ninguno.
    (En SQL Server TRUNCATE es transaccional, a diferencia de MySQL u Oracle.)

    Las validaciones corren DESPUES del COMMIT, fuera de la transaccion: son
    observacion de datos ya confirmados, y mantenerlas afuera evita sostener
    bloqueos sobre la tabla mientras se la recorre.
*/

USE WWI_Staging;
GO

CREATE OR ALTER PROCEDURE etl.usp_LoadSalesOrders
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- ante cualquier error, deshace la transaccion automaticamente

    DECLARE @BatchId    UNIQUEIDENTIFIER = NEWID();
    DECLARE @RowsLoaded INT;
    DECLARE @BaselineRows INT;
    DECLARE @Msg NVARCHAR(400);

    /*  El registro del arranque va FUERA de la transaccion: si estuviera adentro,
        el ROLLBACK lo borraria y las corridas fallidas no dejarian rastro.
        StartedAt no se menciona — lo completa su DEFAULT.                          */
    INSERT INTO etl.LoadBatch (LoadBatchId, SchemaName, TableName, Status)
    VALUES (@BatchId, N'Sales', N'Orders', N'Running');

    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE Sales.Orders;

        INSERT INTO Sales.Orders (
            OrderID,
            CustomerID,
            SalespersonPersonID,
            PickedByPersonID,
            ContactPersonID,
            BackorderOrderID,
            OrderDate,
            ExpectedDeliveryDate,
            CustomerPurchaseOrderNumber,
            IsUndersupplyBackordered,
            Comments,
            DeliveryInstructions,
            InternalComments,
            PickingCompletedWhen,
            LastEditedBy,
            LastEditedWhen,
            LoadBatchId
        )
        SELECT
            OrderID,
            CustomerID,
            SalespersonPersonID,
            PickedByPersonID,
            ContactPersonID,
            BackorderOrderID,
            OrderDate,
            ExpectedDeliveryDate,
            CustomerPurchaseOrderNumber,
            IsUndersupplyBackordered,
            Comments,
            DeliveryInstructions,
            InternalComments,
            PickingCompletedWhen,
            LastEditedBy,
            LastEditedWhen,
            @BatchId
        FROM WideWorldImporters.Sales.Orders;   -- tres partes: cruza el limite de la base

        SET @RowsLoaded = @@ROWCOUNT;   -- pegado al INSERT: cualquier statement intermedio lo pisa

        SELECT @BaselineRows = AVG(RowsLoaded)
        FROM (
            SELECT TOP (5) RowsLoaded
            FROM etl.LoadBatch
            WHERE SchemaName = N'Sales'
              AND TableName  = N'Orders'
              AND Status     = N'Succeeded'
              AND RowsLoaded IS NOT NULL
            ORDER BY StartedAt DESC
        ) AS h;
        
        IF @BaselineRows IS NOT NULL AND @RowsLoaded < @BaselineRows * 0.8
        BEGIN
            SET @Msg = CONCAT(
                N'Caida de volumen en Sales.Orders: se cargaron ', @RowsLoaded,
                N' filas contra una linea base de ', @BaselineRows,
                N' (umbral 80%%). Carga revertida.');

            THROW 50001, @Msg, 1;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        /*  Orden obligatorio: primero deshacer, despues registrar, al final relanzar.
            Registrar antes del ROLLBACK haria que el propio ROLLBACK borre el registro,
            y con XACT_ABORT ON la transaccion queda condenada — no admite escrituras
            hasta deshacerla.                                                          */
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        UPDATE etl.LoadBatch
        SET EndedAt      = SYSUTCDATETIME(),
            Status       = N'Failed',
            ErrorNumber  = ERROR_NUMBER(),
            ErrorMessage = ERROR_MESSAGE()
        WHERE LoadBatchId = @BatchId;

        /*  Sin THROW el procedure terminaria normalmente y le reportaria exito a
            quien lo llamo — un Agent Job marcaria el job en verde tras una carga fallida. */
        THROW;
    END CATCH

    UPDATE etl.LoadBatch
    SET EndedAt    = SYSUTCDATETIME(),
        Status     = N'Succeeded',
        RowsLoaded = @RowsLoaded
    WHERE LoadBatchId = @BatchId;

    EXEC etl.usp_ValidateSalesOrders @BatchId;
END;
GO
