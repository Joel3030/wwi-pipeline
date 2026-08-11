    EXEC msdb.dbo.sp_add_operator
    @name          = N'Joel',
    @enabled       = 1,
    @email_address = N'agathosoft@gmail.com';

EXEC msdb.dbo.sp_update_job
    @job_name                   = N'WWI Staging - Load Sales.Orders',
    @notify_level_email         = 2,
    @notify_email_operator_name = N'Joel';