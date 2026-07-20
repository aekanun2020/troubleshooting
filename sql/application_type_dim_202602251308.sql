-- TestDB.dbo.application_type_dim definition

-- Drop table

-- DROP TABLE TestDB.dbo.application_type_dim;

CREATE TABLE TestDB.dbo.application_type_dim (
	[index] bigint NULL,
	application_type varchar(MAX) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	application_type_id bigint NULL
);

INSERT INTO TestDB.dbo.application_type_dim ([index],application_type,application_type_id) VALUES
	 (0,N'Individual',0),
	 (1,N'Joint App',1);
