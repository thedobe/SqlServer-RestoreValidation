USE []
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
CREATE PROCEDURE [dbo].[usp_db_restore_validation_create_tables]
	-- Add the parameters for the stored procedure here
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    -- Insert statements for procedure here

	if not exists (select [name] from sys.tables where [name] = 'db_restore_validation_history')
	create table [dbo].[db_restore_validation_history] (
		[id] [int] identity(1,1) NOT NULL,
		[server_name] [sysname] NOT NULL,
		[database_name] [sysname] NOT NULL,
		[backup_minutes] [int] NOT NULL,
		[backup_location] [varchar](2000) NOT NULL,
		[backup_size_gb] [float] NOT NULL,
		[restore_minutes] [int] NULL,
		[restore_datetime] [datetime] NOT NULL,
		[restore_location] [varchar](2000) NOT NULL,
		[is_valid] [bit] NOT NULL,
		primary key clustered ([id] asc) 
	)

	if not exists (select [name] from sys.tables where [name] = 'db_restore_validation_ex_history')
	create table [dbo].[db_restore_validation_ex_history] (
		[id] [int] identity(1,1) NOT NULL,
		[server_name] [sysname] NOT NULL,
		[database_name] [sysname] NOT NULL,
		[backup_minutes] [int] NOT NULL,
		[backup_location] [varchar](2000) NOT NULL,
		[backup_size_gb] [float] NOT NULL,
		[restore_datetime] [datetime] NOT NULL,
		[ex_reason] [varchar](2000) NOT NULL,
		primary key clustered ([id] asc) 
	)
END
