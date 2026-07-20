-- TestDB.dbo.home_ownership_dim definition

-- Drop table

-- DROP TABLE TestDB.dbo.home_ownership_dim;

CREATE TABLE TestDB.dbo.home_ownership_dim (
	home_ownership varchar(MAX) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	home_ownership_id bigint NULL
);

INSERT INTO TestDB.dbo.home_ownership_dim (home_ownership,home_ownership_id) VALUES
	 (N'MORTGAGE',0),
	 (N'RENT',1),
	 (N'OWN',2),
	 (N'ANY',3),
	 (N'NONE',4);
