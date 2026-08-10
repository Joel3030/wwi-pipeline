/*
    01_database.sql
    Crea la base de datos de staging (capa bronze).

    Se ejecuta UNA sola vez.

    Recovery model SIMPLE: los datos de staging son reproducibles — si se pierden, se
    regeneran corriendo la carga otra vez. FULL exigiria backups de log periodicos para
    evitar que el log crezca sin limite, y no aporta nada sobre datos regenerables.
*/

CREATE DATABASE WWI_Staging;
GO

ALTER DATABASE WWI_Staging SET RECOVERY SIMPLE;
GO
