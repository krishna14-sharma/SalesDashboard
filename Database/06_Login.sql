/* =====================================================================
   Login against dbo.Usertab4
   Safe to re-run.

   Usertab4.Pwd is varbinary, so this procedure can check the password
   in the common ways it may have been stored:
     PWDENCRYPT  : PWDENCRYPT('secret')                      (checked with PWDCOMPARE)
     SHA2_256    : HASHBYTES('SHA2_256', 'secret')
     SHA1        : HASHBYTES('SHA1', 'secret')
     MD5         : HASHBYTES('MD5', 'secret')
     PASSPHRASE  : ENCRYPTBYPASSPHRASE('<key>', 'secret')    (needs the key in Web.config)
     PLAIN       : CONVERT(varbinary(50), 'secret')
   Each is tried for both varchar and nvarchar text.

   @Mode = 'AUTO' tries them in the order above. Once you know which one
   your system uses, set it in Web.config (Login.PasswordMode) so only that
   method is accepted.

   ---- Which method does my table use? ----
   Run this with a user name and password you know are correct:
       EXEC dbo.usp_App_Login @Uname = 'admin', @Password = N'the-password';
   The [Method] column of the row returned is your method. No row = no match.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.usp_App_Login', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_App_Login;
GO
CREATE PROCEDURE dbo.usp_App_Login
    @Uname      varchar(15),
    @Password   nvarchar(100),
    @Mode       varchar(20)   = 'AUTO',
    @Passphrase nvarchar(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pv varchar(100) = CONVERT(varchar(100), @Password);   -- same text as varchar
    SET @Mode = UPPER(ISNULL(NULLIF(LTRIM(RTRIM(@Mode)), ''), 'AUTO'));
    SET @Passphrase = NULLIF(@Passphrase, N'');

    /* Returns one row only when the user exists AND the password matches. */
    SELECT TOP (1)
            u.Uname,
            u.[Role],
            u.dept,
            u.staff,
            u.uo,
            IsUnAuth = ISNULL(u.isUnAuth, 0),
            m.Method
    FROM    dbo.Usertab4 u
    CROSS APPLY (
        SELECT TOP (1) v.Method
        FROM (VALUES
            (1, 'PWDENCRYPT', CASE WHEN PWDCOMPARE(@Password, u.Pwd) = 1 THEN 1 ELSE 0 END),
            (2, 'SHA2_256',   CASE WHEN u.Pwd = HASHBYTES('SHA2_256', @pv) OR u.Pwd = HASHBYTES('SHA2_256', @Password) THEN 1 ELSE 0 END),
            (3, 'SHA1',       CASE WHEN u.Pwd = HASHBYTES('SHA1', @pv)     OR u.Pwd = HASHBYTES('SHA1', @Password)     THEN 1 ELSE 0 END),
            (4, 'MD5',        CASE WHEN u.Pwd = HASHBYTES('MD5', @pv)      OR u.Pwd = HASHBYTES('MD5', @Password)      THEN 1 ELSE 0 END),
            (5, 'PASSPHRASE', CASE WHEN @Passphrase IS NOT NULL
                                    AND ( DECRYPTBYPASSPHRASE(@Passphrase, u.Pwd) = CONVERT(varbinary(200), @pv)
                                       OR DECRYPTBYPASSPHRASE(@Passphrase, u.Pwd) = CONVERT(varbinary(200), @Password) )
                                   THEN 1 ELSE 0 END),
            (6, 'PLAIN',      CASE WHEN u.Pwd = CONVERT(varbinary(50), @pv) OR u.Pwd = CONVERT(varbinary(50), @Password) THEN 1 ELSE 0 END)
        ) v (Ord, Method, Ok)
        WHERE v.Ok = 1
          AND (@Mode = 'AUTO' OR v.Method = @Mode)
        ORDER BY v.Ord
    ) m
    WHERE   u.Uname = @Uname;
END
GO
