import std.stdio;
import lited;
import std.conv;
import std.string;

void printVersions()
{
	writeln("SQLITE_VERSION=", SQLITE_VERSION);
	writeln("sqlite3_libversion()=", to!string(sqlite3_libversion()));
}

extern (C)
{
	// Directly copied from https://github.com/SelimOzel/dlang-sqlite-interface/blob/main/app.d
	static int callback(void* NotUsed, int argc, char** argv, char** azColName)
	{
		int i;
		for (i = 0; i < argc; i++)
		{
			printf("%s = %s\n", azColName[i], argv[i] ? argv[i] : "NULL");
		}
		printf("\n");
		return 0;
	}
}

void runTest(sqlite3* db)
{
	char* zErrMsg;
	string ddl = "create table if not exists test_table (first_name varchar, lastname varchar);";
	auto ret = sqlite3_exec(db, ddl.toStringz(), &callback, null, &zErrMsg);
	assert(ret == SQLITE_OK);
}

void testInMemDatabase()
{
	sqlite3* db;
	auto dbName = ":memory:";
	auto ret = sqlite3_open(toStringz(dbName), &db);
	scope (exit)
	{
		ret = sqlite3_close(db);
		assert(ret == SQLITE_OK);
	}
	scope (failure)
	{
		writeln("Can't open database: " ~ to!string(sqlite3_errmsg(db)));
	}
	assert(ret == SQLITE_OK);
	runTest(db);
}

void testDatabasePersisted()
{
	sqlite3* db;
	auto dbName = "test.sqlite";
	auto ret = sqlite3_open(toStringz(dbName), &db);
	assert(ret == SQLITE_OK);
	scope (exit)
	{
		ret = sqlite3_close(db);
		assert(ret == SQLITE_OK);
	}
	scope (failure)
	{
		writeln("Can't open database: " ~ to!string(sqlite3_errmsg(db)));
	}
	runTest(db);
}

void main()
{
	printVersions();
	testInMemDatabase();
	testDatabasePersisted();
}
