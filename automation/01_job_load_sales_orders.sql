USE msdb;
GO

DECLARE @JobName NVARCHAR(128) = N'WWI Staging - Load Sales.Orders';

/*  Re-ejecutable: no existe "CREATE OR ALTER JOB", asi que el idioma es
    borrar y volver a crear.  */
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;

/* 1) El job */
EXEC msdb.dbo.sp_add_job
    @job_name         = @JobName,
    @enabled          = 1,
    @description      = N'Carga completa de WideWorldImporters.Sales.Orders hacia WWI_Staging.',
    @owner_login_name = N'sa';

/* 2) El paso */
EXEC msdb.dbo.sp_add_jobstep
    @job_name          = @JobName,
    @step_id           = 1,
    @step_name         = N'Ejecutar etl.usp_LoadSalesOrders',
    @subsystem         = N'TSQL',
    @database_name     = N'WWI_Staging',
    @command           = N'EXEC etl.usp_LoadSalesOrders;',
    @retry_attempts    = 1,
    @retry_interval    = 5,
    @on_success_action = 1,
    @on_fail_action    = 2;

/* 3) La programacion */
EXEC msdb.dbo.sp_add_jobschedule
    @job_name          = @JobName,
    @name              = N'Diario 02:00',
    @freq_type         = 4,
    @freq_interval     = 1,
    @active_start_time = 020000;

/* 4) Registrarlo en el servidor local */
EXEC msdb.dbo.sp_add_jobserver
    @job_name    = @JobName,
    @server_name = N'(local)';
GO