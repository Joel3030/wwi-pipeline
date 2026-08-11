/*
    04_usp_ValidateSalesOrders.sql
    Validaciones de calidad sobre Sales.Orders ya cargada.

    Re-ejecutable (CREATE OR ALTER).

    Estrategia: log & continue. Registra los problemas encontrados en
    etl.ValidationLog pero NO frena nada. Abortar una carga de 73.595 filas buenas
    por unas pocas sospechosas es mala relacion costo/beneficio; el fail-fast
    corresponde a la capa resumen, donde ya no se quieren propagar datos rotos.

    Esta separado de usp_LoadSalesOrders para poder ejecutarlo de forma aislada.
    Si estuvieran juntos, seria imposible probarlo con datos sucios: el TRUNCATE de
    la carga borraria los datos de prueba antes de que las validaciones los vieran.
    Ver tests/negative_tests.sql.

    Recibe @BatchId en vez de generarlo: los registros del log tienen que quedar
    atados a la corrida que los origino.
*/

USE WWI_Staging;
GO

CREATE OR ALTER PROCEDURE etl.usp_ValidateSalesOrders
    @BatchId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NullCustomerCount            INT;
    DECLARE @NullSalespersonPersonIDCount INT;
    DECLARE @NullContactPersonIDCount     INT;
    DECLARE @NullOrderDateCount           INT;
    DECLARE @DuplicateOrderIDCount        INT;

    /*  Agregacion condicional: los cuatro conteos en UNA sola pasada por la tabla,
        en vez de cuatro SELECT COUNT(*) con WHERE.

        Se usa SUM(CASE ... ELSE 0) y no COUNT(CASE ... END), aunque ambas formas
        son idiomaticas y dan el mismo resultado. La version con COUNT genera NULL
        en cada fila que no cumple la condicion, y con ANSI_WARNINGS ON (el default)
        eso hace que SQL Server emita el warning 8153 "Null value is eliminated by
        an aggregate". Es inofensivo, pero se escribiria en el historial del Agent
        Job en cada corrida nocturna, y el ruido permanente en logs operativos
        entrena a la gente a ignorarlos. Con ELSE 0 no se generan nulos.

        Nota: SUM sobre cero filas devuelve NULL (COUNT devolveria 0). El
        WHERE AffectedRowCount > 0 del INSERT lo filtra igual, asi que no cambia
        el comportamiento.                                                          */
    SELECT
        @NullCustomerCount            = SUM(CASE WHEN CustomerID          IS NULL THEN 1 ELSE 0 END),
        @NullSalespersonPersonIDCount = SUM(CASE WHEN SalespersonPersonID IS NULL THEN 1 ELSE 0 END),
        @NullContactPersonIDCount     = SUM(CASE WHEN ContactPersonID     IS NULL THEN 1 ELSE 0 END),
        @NullOrderDateCount           = SUM(CASE WHEN OrderDate           IS NULL THEN 1 ELSE 0 END)
    FROM Sales.Orders;

    /*  El chequeo de duplicados no entra en la pasada anterior porque necesita
        su propio GROUP BY.                                                        */
    SELECT @DuplicateOrderIDCount = COUNT(*)
    FROM (
        SELECT OrderID
        FROM Sales.Orders
        GROUP BY OrderID
        HAVING COUNT(*) > 1
    ) AS Duplicados;

    /*  Table value constructor: una tabla de 5 filas armada al vuelo, sin crear nada.
        El WHERE reemplaza cinco bloques IF separados.
        Ventaja sobre los IF repetidos: la lista de columnas y los literales
        'Sales'/'Orders' se escriben UNA vez, asi que es estructuralmente imposible
        que se desincronicen entre reglas.                                          */
    INSERT INTO etl.ValidationLog (
        LoadBatchId,
        SchemaName,
        TableName,
        RuleName,
        AffectedRowCount
    )
    SELECT
        @BatchId,
        N'Sales',
        N'Orders',
        v.RuleName,
        v.AffectedRowCount
    FROM (VALUES
        (N'CustomerID_NULL',          @NullCustomerCount),
        (N'SalespersonPersonID_NULL', @NullSalespersonPersonIDCount),
        (N'ContactPersonID_NULL',     @NullContactPersonIDCount),
        (N'OrderDate_NULL',           @NullOrderDateCount),
        (N'OrderID_DUPLICATE',        @DuplicateOrderIDCount)
    ) AS v (RuleName, AffectedRowCount)
    WHERE v.AffectedRowCount > 0;
END;
GO
