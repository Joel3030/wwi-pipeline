/*
    02_database_mail.template.sql
    PLANTILLA — Configuracion de Database Mail para las alertas del pipeline.

    ESTE ARCHIVO NO TIENE CREDENCIALES Y SI SE VERSIONA.

    Para usarlo: copiarlo a "02_database_mail.local.sql", completar los
    marcadores <...> y ejecutarlo. El .gitignore excluye cualquier archivo con
    "local" en el nombre, asi que la copia con la password queda fuera del repo.

        cp automation/02_database_mail.template.sql automation/02_database_mail.local.sql

    ---------------------------------------------------------------------------
    QUE COMPLETAR

    <EMAIL_REMITENTE>   la cuenta desde la que salen las alertas
    <SERVIDOR_SMTP>     p. ej. smtp.gmail.com
    <PUERTO>            587 para STARTTLS
    <USUARIO_SMTP>      normalmente el mismo email
    <APP_PASSWORD>      contrasena de aplicacion, NO la contrasena de la cuenta

    Con Gmail hace falta una App Password: se genera en la configuracion de
    seguridad de la cuenta de Google, requiere verificacion en dos pasos, y es
    revocable de forma independiente. La contrasena normal de la cuenta no
    funciona y ademas seria mucho peor idea: no se puede revocar sin cambiar el
    acceso a toda la cuenta.

    ---------------------------------------------------------------------------
    POR QUE ESTO EXISTE

    etl.ValidationLog es una tabla PASIVA: solo sirve si alguien la consulta.
    Un pipeline que detecta problemas y no avisa no es observable.

    Y hay una razon de fondo por la que el aviso lo manda el motor y no una
    persona ni un asistente: Database Mail es un SERVICIO con sus propias
    credenciales SMTP, asi que envia solo, a las 2 AM, sin nadie mirando. La
    automatizacion de un pipeline no puede depender de que alguien este presente.

    Database Mail es ASINCRONICO: sp_send_dbmail encola el mensaje via Service
    Broker y devuelve el control de inmediato. Que el procedure termine bien NO
    significa que el correo haya salido. El estado real esta en
    msdb.dbo.sysmail_allitems y los fallos en msdb.dbo.sysmail_event_log.
    --------------------------------------------------------------------------- */

USE msdb;
GO

/*  Habilitar Database Mail (esta desactivado por defecto).
    Es una opcion avanzada, de ahi el show advanced options.  */
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'Database Mail XPs', 1;
RECONFIGURE;
GO

/*  1) LA CUENTA — los datos tecnicos del SMTP.
    Es el "como se envia": servidor, puerto, credenciales.  */
EXEC msdb.dbo.sysmail_add_account_sp
    @account_name    = N'WWI Pipeline Alerts',
    @description     = N'Cuenta SMTP para alertas del pipeline',
    @email_address   = N'<EMAIL_REMITENTE>',
    @display_name    = N'WWI Pipeline',
    @mailserver_name = N'<SERVIDOR_SMTP>',
    @port            = <PUERTO>,
    @enable_ssl      = 1,
    @username        = N'<USUARIO_SMTP>',
    @password        = N'<APP_PASSWORD>';   -- <<< NUNCA COMMITEAR ESTE VALOR
GO

/*  2) EL PERFIL — la capa de indireccion que consume Agent.
    Agent nunca nombra una cuenta: nombra un perfil. Asi se puede cambiar el
    proveedor de correo, o poner varias cuentas de respaldo, sin tocar ningun
    job. Es la misma idea que una cadena de conexion con nombre.  */
EXEC msdb.dbo.sysmail_add_profile_sp
    @profile_name = N'WWI Pipeline Alerts',
    @description  = N'Perfil de alertas del pipeline de staging';
GO

/*  3) Asociar cuenta al perfil.
    sequence_number define el orden de intento: si la cuenta 1 falla, se
    intenta la 2. Con una sola cuenta es irrelevante, pero es el mecanismo de
    failover del correo.  */
EXEC msdb.dbo.sysmail_add_profileaccount_sp
    @profile_name    = N'WWI Pipeline Alerts',
    @account_name    = N'WWI Pipeline Alerts',
    @sequence_number = 1;
GO

/*  4) Dar acceso al perfil. SIN ESTO, AGENT NO LO VE.
    Es el paso que se olvida: todo queda configurado, sp_send_dbmail manual
    funciona, y los jobs no mandan nada.  */
EXEC msdb.dbo.sysmail_add_principalprofile_sp
    @profile_name   = N'WWI Pipeline Alerts',
    @principal_name = N'public',
    @is_default     = 1;
GO

/*  5) Decirle a SQL Server Agent que use Database Mail.
    Requiere REINICIAR el servicio Agent para tomar efecto.  */
EXEC msdb.dbo.sp_set_sqlagent_properties
    @use_databasemail          = 1,
    @databasemail_profile      = N'WWI Pipeline Alerts',
    @email_save_in_sent_folder = 1;
GO

/* ---------------------------------------------------------------------------
   VERIFICACION
   --------------------------------------------------------------------------- */

-- Enviar una prueba
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = N'WWI Pipeline Alerts',
    @recipients   = N'<EMAIL_DESTINO>',
    @subject      = N'Prueba de Database Mail — WWI Pipeline',
    @body         = N'Si llega esto, el perfil funciona.';

-- Estado real de los envios (recordar: es asincronico)
SELECT TOP 10 mailitem_id, recipients, subject, sent_status, sent_date
FROM msdb.dbo.sysmail_allitems
ORDER BY mailitem_id DESC;

-- Errores de envio
SELECT TOP 10 log_date, event_type, description
FROM msdb.dbo.sysmail_event_log
ORDER BY log_id DESC;
GO
