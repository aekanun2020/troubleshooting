-- TestDB.dbo.emp_length_dim definition

-- Drop table

-- DROP TABLE TestDB.dbo.emp_length_dim;

CREATE TABLE TestDB.dbo.emp_length_dim (
	[index] bigint NULL,
	emp_length varchar(MAX) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	emp_length_id bigint NULL
);

INSERT INTO TestDB.dbo.emp_length_dim ([index],emp_length,emp_length_id) VALUES
	 (0,N'6 years',0),
	 (1,N'9 years',1),
	 (2,N'5 years',2),
	 (3,N'10+ years',3),
	 (4,N'8 years',4),
	 (5,N'3 years',5),
	 (6,N'2 years',6),
	 (7,N'< 1 year',7),
	 (8,N'4 years',8),
	 (9,N'1 year',9);
INSERT INTO TestDB.dbo.emp_length_dim ([index],emp_length,emp_length_id) VALUES
	 (10,N'N/A',10),
	 (11,N'7 years',11);
