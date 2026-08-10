/*
    02_schemas.sql
    Crea los schemas de la base de staging.

    Se ejecuta UNA sola vez.

    Sales  -> espejo del schema homonimo del origen. Contiene EXACTAMENTE las tablas que
              existen en WideWorldImporters.Sales, ni una mas (source-aligned staging).
    etl    -> metadata del pipeline: log de validaciones y control de corridas.

    CREATE SCHEMA tiene que ser la unica instruccion de su lote, de ahi los GO.
*/

USE WWI_Staging;
GO

CREATE SCHEMA Sales;
GO

CREATE SCHEMA etl;
GO
