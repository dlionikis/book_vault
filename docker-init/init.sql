CREATE DATABASE book_vault_shadow OWNER postgres;
GRANT ALL PRIVILEGES ON DATABASE book_vault TO postgres;
GRANT ALL PRIVILEGES ON DATABASE book_vault_shadow TO postgres;
