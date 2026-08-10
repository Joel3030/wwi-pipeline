/*
    negative_tests.sql
    Pruebas del CAMINO DE ERROR del pipeline de staging.

    Por que existe este archivo:
    El dataset de WideWorldImporters esta limpio, asi que en operacion normal las
    validaciones siempre dan 0 y el manejo de errores nunca se ejecuta. Codigo que
    nunca corre es codigo que no se sabe si funciona — y en este proyecto eso ya
    escondio bugs reales dos veces (una columna NOT NULL faltante en un INSERT que
    solo se ejecutaba ante fallas, y un procedure desplegado que no era el que se
    creia).

    Estas pruebas fuerzan esas condiciones a proposito.

    IMPORTANTE: ejecutar bloque por bloque, no el archivo entero de una.
    Cada bloque deja el sistema en estado limpio al terminar.
*/

USE WWI_Staging;
GO


/* =============================================================================
   TEST 1 — Idempotencia
   Un proceso que se va a automatizar corre cientos de veces, no una. Dos corridas
   seguidas tienen que dejar el mismo estado que una sola.
   ============================================================================= */

EXEC etl.usp_LoadSalesOrders;
EXEC etl.usp_LoadSalesOrders;

--  Se espera: 73595 filas y UN solo batch distinto.
--  El conteo de batches es mejor prueba que el de filas: demuestra que la tabla
--  contiene datos de una sola corrida, no que los numeros coinciden de casualidad.
SELECT COUNT(*) AS Filas, COUNT(DISTINCT LoadBatchId) AS Batches
FROM Sales.Orders;
GO


/* =============================================================================
   TEST 2 — Rollback ante fallo a mitad de carga
   Se espera que los datos de la carga ANTERIOR sobrevivan intactos, y que quede
   registrada una corrida Failed en etl.LoadBatch.
   ============================================================================= */

-- Estado de partida
SELECT COUNT(*) AS AntesDelTest FROM Sales.Orders;   -- se espera 73595
GO

-- Saboteador: un trigger que hace fallar cualquier INSERT sobre la tabla.
-- Vive FUERA del procedure y se borra al terminar: el andamio de prueba no
-- convive con el codigo que prueba.
CREATE TRIGGER Sales.trg_SimularFallo
ON Sales.Orders
AFTER INSERT
AS
    THROW 50000, 'Fallo simulado para probar el rollback', 1;
GO

-- Se espera que ESTO FALLE con el mensaje de arriba.
-- Que corra en verde seria el bug: significaria que THROW no esta relanzando.
EXEC etl.usp_LoadSalesOrders;
GO

-- Se espera 73595: el ROLLBACK deshizo el TRUNCATE junto con el INSERT.
SELECT COUNT(*) AS DespuesDelFallo FROM Sales.Orders;

-- Se espera una fila Status = 'Failed', con ErrorNumber 50000, el mensaje del
-- trigger, y RowsLoaded en NULL.
SELECT TOP 1 * FROM etl.LoadBatch ORDER BY StartedAt DESC;
GO

-- Limpieza
DROP TRIGGER Sales.trg_SimularFallo;
GO

EXEC etl.usp_LoadSalesOrders;
SELECT COUNT(*) AS Restaurado FROM Sales.Orders;   -- se espera 73595
GO


/* =============================================================================
   TEST 3 — Deteccion de problemas de calidad
   Ensucia una fila a proposito y ejecuta el procedure REAL de validacion.

   Se ejecuta usp_ValidateSalesOrders directamente, no usp_LoadSalesOrders: este
   ultimo empieza con un TRUNCATE que borraria la fila sucia antes de mirarla.
   Poder hacer esto es la razon por la que carga y validacion estan separadas.
   ============================================================================= */

-- Carga limpia de partida
EXEC etl.usp_LoadSalesOrders;
GO

-- Ensuciar exactamente una fila
UPDATE TOP (1) Sales.Orders
SET CustomerID = NULL
WHERE CustomerID IS NOT NULL;
GO

-- GUID reconocible para distinguir a simple vista las filas de test de las reales
EXEC etl.usp_ValidateSalesOrders '00000000-0000-0000-0000-000000000001';
GO

-- Se espera UNA fila: RuleName = 'CustomerID_NULL', AffectedRowCount = 1
SELECT * FROM etl.ValidationLog
WHERE LoadBatchId = '00000000-0000-0000-0000-000000000001';
GO

-- Limpieza
DELETE FROM etl.ValidationLog
WHERE LoadBatchId = '00000000-0000-0000-0000-000000000001';

EXEC etl.usp_LoadSalesOrders;
SELECT COUNT(*) AS NullCustomersRestantes
FROM Sales.Orders WHERE CustomerID IS NULL;   -- se espera 0
GO
