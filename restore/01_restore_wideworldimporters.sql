/*
    01_restore_wideworldimporters.sql
    Paso 1 — Restaurar la base de origen.

    El .bak NO esta en el repo: pesa 121 MB, es binario y es un archivo de
    terceros. Se baja del repo oficial de Microsoft:

        https://github.com/Microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0
        archivo: WideWorldImporters-Full.bak

    Un repo versiona lo que uno construyo, no lo que descargo. Mismo criterio que
    node_modules: se versiona la declaracion de la dependencia, no la dependencia.

    ---------------------------------------------------------------------------
    ANTES DE RESTAURAR: leer el backup

    RESTORE FILELISTONLY lee el contenido del .bak sin restaurar nada. Hace falta
    porque el backup guarda las RUTAS ABSOLUTAS de la maquina donde se genero
    (una instalacion en D:\ de SQL Server 2016). Si esas rutas no existen aca,
    el restore falla con "directory lookup failed". Por eso cada archivo necesita
    su WITH MOVE.
    --------------------------------------------------------------------------- */

RESTORE FILELISTONLY
FROM DISK = N'C:\ruta\a\WideWorldImporters-Full.bak';
GO

/* ---------------------------------------------------------------------------
   Nombres logicos del backup (verificados con la consulta de arriba):

     WWI_Primary          D   filegroup PRIMARY
     WWI_UserData         D   filegroup USERDATA
     WWI_Log              L   log de transacciones
     WWI_InMemory_Data_1  S   contenedor In-Memory OLTP

   El cuarto es el que sorprende. Type = 'S' es un filegroup MEMORY_OPTIMIZED_DATA
   y su destino es un DIRECTORIO, no un archivo: SQL Server crea ahi una carpeta
   con multiples contenedores. Si se lo trata como archivo, el restore falla.

   WideWorldImporters usa In-Memory OLTP para tablas calientes de la aplicacion.
   No afecta al pipeline —se leen como tablas normales— pero condiciona el
   restore, y en ediciones que no soportan In-Memory la base no se puede montar.
   --------------------------------------------------------------------------- */

/* ===========================================================================
   OPCION A — Windows / SQL Server instalado localmente
   =========================================================================== */
RESTORE DATABASE WideWorldImporters
FROM DISK = N'C:\ruta\a\WideWorldImporters-Full.bak'
WITH
    MOVE N'WWI_Primary'         TO N'C:\SQLData\WideWorldImporters.mdf',
    MOVE N'WWI_UserData'        TO N'C:\SQLData\WideWorldImporters_UserData.ndf',
    MOVE N'WWI_Log'             TO N'C:\SQLData\WideWorldImporters.ldf',
    MOVE N'WWI_InMemory_Data_1' TO N'C:\SQLData\WideWorldImporters_InMemory_Data_1',
    RECOVERY,
    STATS = 5;
GO

/* ===========================================================================
   OPCION B — SQL Server 2022 en Docker (Linux). Es el entorno de la MacBook.

   Las rutas son las del contenedor, no las del Mac. Copiar el .bak adentro:

       docker cp WideWorldImporters-Full.bak <contenedor>:/var/opt/mssql/backup/

   Ojo con dos cosas en Linux:
     - las rutas usan / y son sensibles a mayusculas
     - el usuario mssql tiene que poder leer el archivo; si da error de permisos,
       revisar el owner del archivo dentro del contenedor
   =========================================================================== */
/*
RESTORE DATABASE WideWorldImporters
FROM DISK = N'/var/opt/mssql/backup/WideWorldImporters-Full.bak'
WITH
    MOVE N'WWI_Primary'         TO N'/var/opt/mssql/data/WideWorldImporters.mdf',
    MOVE N'WWI_UserData'        TO N'/var/opt/mssql/data/WideWorldImporters_UserData.ndf',
    MOVE N'WWI_Log'             TO N'/var/opt/mssql/data/WideWorldImporters.ldf',
    MOVE N'WWI_InMemory_Data_1' TO N'/var/opt/mssql/data/WideWorldImporters_InMemory_Data_1',
    RECOVERY,
    STATS = 5;
GO
*/

/* ---------------------------------------------------------------------------
   RECOVERY vs NORECOVERY

   RECOVERY cierra la cadena de restore y deja la base utilizable. Es lo correcto
   aca porque se restaura un unico backup completo.

   NORECOVERY dejaria la base en "Restoring...", inaccesible, esperando mas
   backups (diferenciales o de log). Es lo que se usa al restaurar una cadena.
   --------------------------------------------------------------------------- */

/* ---------------------------------------------------------------------------
   VERIFICACION — correr despues del restore.
   Los numeros son la linea base del proyecto: si no coinciden, el origen no es
   el mismo y las validaciones del pipeline van a comparar contra otra realidad.
   --------------------------------------------------------------------------- */
USE WideWorldImporters;
GO

SELECT
    (SELECT COUNT(*) FROM Sales.Orders)      AS Orders,        -- esperado:  73.595
    (SELECT COUNT(*) FROM Sales.OrderLines)  AS OrderLines,    -- esperado: 231.412
    (SELECT COUNT(*) FROM Sales.Customers)   AS Customers,     -- esperado:     663
    (SELECT COUNT(*) FROM Warehouse.StockItems) AS StockItems; -- esperado:     227
GO

/* ---------------------------------------------------------------------------
   PRODUCCION SIMULADA: esta base NUNCA se modifica.

   Es el origen del pipeline y representa un sistema transaccional ajeno. Todo lo
   que el proyecto construye vive en WWI_Staging y en la capa resumen. Dejarla
   en solo lectura es opcional, pero hace explicito el contrato:

       ALTER DATABASE WideWorldImporters SET READ_ONLY;

   (No se activa por defecto: las tablas temporales de sistema y algunas
   operaciones de mantenimiento requieren escritura.)
   --------------------------------------------------------------------------- */
