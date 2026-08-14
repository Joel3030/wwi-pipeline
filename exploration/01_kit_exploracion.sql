/*
    01_kit_exploracion.sql
    Paso 1 — Explorar y perfilar una base desconocida.

    Catorce consultas para el primer dia en cualquier base sin documentacion.
    NO modifican nada: son todas de lectura sobre catalogos del sistema.

    El orden importa: van de estructura a contenido, y de lo general a lo
    especifico. Correrlas al reves lleva a perfilar columnas de tablas que
    despues resulta que no se necesitaban.

    Las tres mas subestimadas son la 7 (claves sin FK), la 9 (constraints no
    confiables) y la 13 (tablas puente). Son las que encuentran los problemas
    que explotan mas tarde, cuando ya hay un dashboard mostrando numeros.

    Resultados de este proyecto y decisiones de alcance: ver
    exploration/02_alcance_y_exclusiones.md
*/

USE WideWorldImporters;
GO

/* === ESTRUCTURA ======================================================== */

-- 1. Inventario de tablas por tamano.
--    sys.partitions y no COUNT(*): COUNT escanea cada tabla, bloquea y tarda.
--    index_id IN (0,1) = heap o indice clustered, es decir la tabla misma;
--    sin ese filtro se suman las filas de cada indice no clustered.
SELECT s.name AS SchemaName, t.name AS TableName, p.rows
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
ORDER BY p.rows DESC;

-- 2. Estructura de una tabla (cambiar schema y tabla)
SELECT ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH,
       NUMERIC_PRECISION, NUMERIC_SCALE, IS_NULLABLE, COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'Sales' AND TABLE_NAME = 'Orders'
ORDER BY ORDINAL_POSITION;

-- 3. Buscar una columna en toda la base.
--    Sirve para rastrear un concepto: donde aparece "Customer" muestra el mapa
--    de que tablas participan de ese concepto.
SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE COLUMN_NAME LIKE '%Customer%'
ORDER BY TABLE_SCHEMA, TABLE_NAME;

-- 4. Columnas calculadas.
--    NO SE PUEDEN INSERTAR. Si una aparece en el INSERT del ETL, falla.
--    En WWI, Application.People.SearchName es una de estas.
SELECT OBJECT_SCHEMA_NAME(c.object_id) + '.' + OBJECT_NAME(c.object_id) AS Tabla,
       c.name AS Columna, cc.definition AS Formula, cc.is_persisted
FROM sys.computed_columns cc
JOIN sys.columns c ON c.object_id = cc.object_id AND c.column_id = cc.column_id;

-- 5. Claves primarias. Una PK compuesta cambia el diseno del staging y del hecho.
SELECT s.name AS SchemaName, t.name AS TableName, i.name AS ConstraintName,
       STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS Columnas
FROM sys.indexes i
JOIN sys.tables t ON t.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.is_primary_key = 1
GROUP BY s.name, t.name, i.name
ORDER BY s.name, t.name;

-- 6. Mapa de relaciones: el diagrama entidad-relacion, en texto.
SELECT OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id) AS TablaHija,
       cp.name AS ColumnaHija,
       OBJECT_SCHEMA_NAME(fk.referenced_object_id) + '.' + OBJECT_NAME(fk.referenced_object_id) AS TablaPadre,
       cr.name AS ColumnaPadre, fk.name AS NombreFK,
       fk.delete_referential_action_desc AS AlBorrar
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns cp ON cp.object_id = fkc.parent_object_id AND cp.column_id = fkc.parent_column_id
JOIN sys.columns cr ON cr.object_id = fkc.referenced_object_id AND cr.column_id = fkc.referenced_column_id
ORDER BY TablaHija, NombreFK;

-- 7. Claves SIN FK declarada. Parecen claves foraneas pero no tienen integridad
--    garantizada: pueden apuntar a filas que ya no existen.
--    En WWI, Sales.Orders.BackorderOrderID es el caso: apunta a otro pedido sin
--    FK. Si el ETL hace INNER JOIN por una de estas, descarta filas en silencio.
SELECT OBJECT_SCHEMA_NAME(c.object_id) + '.' + OBJECT_NAME(c.object_id) AS Tabla, c.name AS Columna
FROM sys.columns c
JOIN sys.tables t ON t.object_id = c.object_id
WHERE c.name LIKE '%ID' AND c.name NOT LIKE '%RowID'
  AND NOT EXISTS (SELECT 1 FROM sys.foreign_key_columns fkc
                  WHERE fkc.parent_object_id = c.object_id AND fkc.parent_column_id = c.column_id)
  AND NOT EXISTS (SELECT 1 FROM sys.index_columns ic
                  JOIN sys.indexes i ON i.object_id = ic.object_id AND i.index_id = ic.index_id
                  WHERE ic.object_id = c.object_id AND ic.column_id = c.column_id AND i.is_primary_key = 1)
ORDER BY 1, 2;

-- 8. CHECK constraints: reglas de negocio ejecutables, ya escritas por otro.
--    Son documentacion que no puede mentir, porque el motor la aplica.
SELECT OBJECT_SCHEMA_NAME(cc.parent_object_id) + '.' + OBJECT_NAME(cc.parent_object_id) AS Tabla,
       cc.name AS Constraint_, cc.definition AS Regla
FROM sys.check_constraints cc
ORDER BY 1;

-- 9. Constraints NO CONFIABLES (not trusted).
--    Un constraint rehabilitado sin verificar los datos existentes: el motor lo
--    aplica de aca en adelante pero NO garantiza el pasado. Puede estar violado
--    ahora mismo. Nunca asumir integridad de una de estas.
SELECT name, is_not_trusted, 'CHECK' AS Tipo FROM sys.check_constraints WHERE is_not_trusted = 1
UNION ALL
SELECT name, is_not_trusted, 'FOREIGN KEY' FROM sys.foreign_keys WHERE is_not_trusted = 1;

/* === CONTENIDO (data profiling) ======================================== */

-- 10. Perfil de completitud. Adaptar las columnas a la tabla que se perfile.
SELECT COUNT(*) AS Total,
       SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) AS CustomerID_Null
FROM Sales.Orders;

-- 11. Cardinalidad y rango de fechas.
--     El rango define el rango de DimDate; la cardinalidad estima el tamano de
--     cada dimension.
SELECT COUNT(*) AS Filas, COUNT(DISTINCT CustomerID) AS Clientes,
       MIN(OrderDate) AS Desde, MAX(OrderDate) AS Hasta,
       DATEDIFF(DAY, MIN(OrderDate), MAX(OrderDate)) AS Dias
FROM Sales.Orders;

-- 12. Distribucion de valores: detecta VALORES CENTINELA.
--     Un centinela es un valor que significa "sin dato" sin ser NULL: 1900-01-01,
--     -1, 'N/A', 0. Se detectan por frecuencia anomala, no por tipo.
SELECT TOP (20) IsUndersupplyBackordered, COUNT(*) AS Cantidad,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS Pct
FROM Sales.Orders
GROUP BY IsUndersupplyBackordered
ORDER BY Cantidad DESC;

-- 13. Tablas puente de muchos a muchos: las trampas de FAN-OUT.
--     Heuristica: PK propia + dos o mas FK. Unir un hecho a traves de una de
--     estas MULTIPLICA filas y los importes salen inflados, sin ningun error.
--     En WWI: Warehouse.StockItemStockGroups (442 filas, 227 productos).
SELECT OBJECT_SCHEMA_NAME(t.object_id) + '.' + OBJECT_NAME(t.object_id) AS TablaPuente
FROM sys.tables t
WHERE EXISTS (SELECT 1 FROM sys.indexes i WHERE i.object_id = t.object_id AND i.is_primary_key = 1)
  AND (SELECT COUNT(*) FROM sys.foreign_keys fk WHERE fk.parent_object_id = t.object_id) >= 2
ORDER BY 1;

-- 14. Tablas temporales de sistema: historial de cambios automatico.
--     Son 17 en WWI, entre ellas Sales.Customers y Warehouse.StockItems.
--     Relevante para SCD Tipo 2: el origen YA guarda el historial que
--     normalmente hay que construir a mano.
SELECT s.name + '.' + t.name AS Tabla,
       OBJECT_SCHEMA_NAME(t.history_table_id) + '.' + OBJECT_NAME(t.history_table_id) AS TablaHistorica
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE t.temporal_type = 2
ORDER BY 1;
GO
