-- TestDB.dbo.loan_status_dim definition

-- Drop table

-- DROP TABLE TestDB.dbo.loan_status_dim;

CREATE TABLE TestDB.dbo.loan_status_dim (
	loan_status varchar(MAX) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	loan_status_id bigint NULL
);

INSERT INTO TestDB.dbo.loan_status_dim (loan_status,loan_status_id) VALUES
	 (N'Fully Paid',0),
	 (N'Charged Off',1),
	 (N'Current',2),
	 (N'Late (31-120 days)',3),
	 (N'Default',4),
	 (N'Late (16-30 days)',5),
	 (N'In Grace Period',6);
