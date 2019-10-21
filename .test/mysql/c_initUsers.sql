CREATE TABLE USER_ (
  ID VARCHAR(25) NOT NULL,				# the username is the id
  DELETED CHAR(1) DEFAULT '0',
  KONTAKT_ID VARCHAR(25),				# foreign key to contact table
  LASTUPDATE BIGINT,
  HASHED_PASSWORD VARCHAR(64),			# Currently SHA-256
  SALT VARCHAR(64),						# The SALT used for SHA256_PASSWORD hash
  IS_ACTIVE CHAR(1) DEFAULT '1', 		# Is this account currently active? If not, any log-in is to be prohibited.
  IS_ADMINISTRATOR CHAR(1) DEFAULT '0',	# User is an administrator
  KEYSTORE TEXT,						# For key based authentication or signature purposes
  EXTINFO BLOB,
  PRIMARY KEY (ID)
);

INSERT INTO KONTAKT (ID, BEZEICHNUNG1, BEZEICHNUNG2, EMAIL) VALUES ('fc0e7f0981604b05b1d6fb1b6', 'Familyname', 'Firstname', 'email@domain.com');
INSERT INTO USER_ (ID, IS_ADMINISTRATOR, IS_ACTIVE, KONTAKT_ID) VALUES ('elexisuser', '0', '1', 'fc0e7f0981604b05b1d6fb1b6');