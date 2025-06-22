module sqlite_wrapper;

import lited;
import std.array;
import std.conv;
import std.exception;
import std.format;
import std.stdio;
import std.string;
import vibe.data.json;
import std.logger;

class SQLiteException : Exception
{
    int errorCode;

    this(string msg, int code, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
        this.errorCode = code;
    }
}

struct Database
{
    private sqlite3* db;
    private bool isOpen;
    private Logger logger;

    private static extern (C) void sqliteLogCallback(void* pArg, int iErrCode, const(char)* zMsg) nothrow
    {
        Logger log = cast(Logger) pArg;
        try
        {
            string message = to!string(zMsg);
            if (iErrCode == 0)
            {
                log.info("SQLite: " ~ message);
            }
            else
            {
                log.warningf("SQLite Error [%d]: %s", iErrCode, message);
            }
        }
        catch (Exception e)
        {
            // Silently ignore - cannot propagate exceptions from nothrow
            // Optionally: store error somewhere for later inspection
        }
    }

    this(string dbPath, Logger logger)
    {
        enforce(logger !is null);
        this.logger = logger;
        open(dbPath);
        apply_best_practises();
    }

    this(string dbPath)
    {
        auto logger = new NullLogger();
        this(dbPath, logger);
    }

    this() @disable;

    ~this()
    {
        close();
    }

    void apply_best_practises(int busy_timeout_ms = 100)
    {
        // keeps up to date with SQLite best practises -
        // https://rogerbinns.github.io/apsw/bestpractice.html
        execute(i"PRAGMA busy_timeout = $(busy_timeout_ms);".text);
        execute("PRAGMA foreign_keys = ON;");
        execute("PRAGMA optimize;");
        execute("PRAGMA recursive_triggers = true;");
        execute("PRAGMA journal_mode=WAL;");
        int retCode = sqlite3_config(SQLITE_CONFIG_LOG, &sqliteLogCallback, cast(void*) logger);
        assert(retCode == SQLITE_OK);
    }

    void open(string dbPath)
    {
        if (isOpen)
            return;
        auto ret = sqlite3_open(dbPath.toStringz(), &db);
        if (ret != SQLITE_OK)
        {
            auto error = format("Cannot open database %s: %s", dbPath, to!string(sqlite3_errmsg(db)));
            sqlite3_close(db);
            throw new SQLiteException(error, ret);
        }
        isOpen = true;
    }

    void close()
    {
        scope (exit)
        {
            db = null;
            isOpen = false;
        }
        sqlite3_close(db);
    }

    void execute(string sql)
    {
        enforce(isOpen, "Database is not open");
        char* errorMsg;
        scope (exit)
        {
            if (errorMsg)
            {
                sqlite3_free(errorMsg);
            }
        }
        auto ret = sqlite3_exec(db, sql.toStringz(), null, null, &errorMsg);
        if (ret != SQLITE_OK)
        {
            auto error = format("SQL execution failed: %s", errorMsg ? to!string(errorMsg)
                    : "Unknown error");
            throw new SQLiteException(error, ret);
        }
    }

    auto prepare(string sql)
    {
        enforce(isOpen, "Database is not open");
        return Statement(db, sql);
    }
}

struct Statement
{
    private sqlite3_stmt* stmt;
    private sqlite3* db;
    private bool isFinalized;

    this(sqlite3* database, string sql)
    {
        this.db = database;

        auto ret = sqlite3_prepare_v2(db, sql.toStringz(),
            cast(int) sql.length, &stmt, null);
        if (ret != SQLITE_OK)
        {
            auto error = format("Failed to prepare statement: %s", to!string(sqlite3_errmsg(db)));
            throw new SQLiteException(error, ret);
        }
    }

    ~this()
    {
        finalize();
    }

    void finalize()
    {
        if (!isFinalized && stmt !is null)
        {
            sqlite3_finalize(stmt);
            stmt = null;
            isFinalized = true;
        }
    }

    void reset()
    {
        sqlite3_reset(stmt);
        sqlite3_clear_bindings(stmt);
    }

    void bind(int index, long value)
    {
        sqlite3_bind_int64(stmt, index, value);
    }

    void bind(int index, string value)
    {
        sqlite3_bind_text(stmt, index, value.toStringz(), cast(int) value.length, SQLITE_TRANSIENT);
    }

    void bind(int index, double value)
    {
        sqlite3_bind_double(stmt, index, value);
    }

    void bindNull(int index)
    {
        sqlite3_bind_null(stmt, index);
    }

    void bind(int index, Json jsonData)
    {
        auto jsonString = jsonData.toString();
        auto ret = sqlite3_bind_text(stmt, index, jsonString.toStringz(),
            cast(int) jsonString.length, SQLITE_TRANSIENT);
        if (ret != SQLITE_OK)
        {
            auto error = format("Failed to bind JSON at index %d: %s", index, to!string(
                    sqlite3_errmsg(db)));
            throw new SQLiteException(error, ret);
        }
    }

    void execute()
    {
        auto ret = sqlite3_step(stmt);
        if (ret != SQLITE_DONE && ret != SQLITE_ROW)
        {
            auto error = format("Statement execution failed: %s", to!string(sqlite3_errmsg(db)));
            throw new SQLiteException(error, ret);
        }
        reset();
    }

    auto query()
    {
        return ResultSet(this);
    }
}

struct ResultSet
{
    private Statement* stmt;
    private bool hasData;

    this(ref Statement statement)
    {
        this.stmt = &statement;
        advance();
    }

    private void advance()
    {
        auto ret = sqlite3_step(stmt.stmt);
        hasData = (ret == SQLITE_ROW);
        if (!hasData && ret != SQLITE_DONE)
        {
            auto error = format("Query failed: %s", to!string(sqlite3_errmsg(stmt.db)));
            throw new SQLiteException(error, ret);
        }
    }

    bool empty() const
    {
        return !hasData;
    }

    void popFront()
    {
        advance();
    }

    long getInt(int column)
    {
        return sqlite3_column_int64(stmt.stmt, column);
    }

    string getText(int column)
    {
        auto cstr = sqlite3_column_text(stmt.stmt, column);
        if (!cstr)
        {
            return "";
        }
        return to!string(cast(char*) cstr);
    }

    Json getJson(int column)
    {
        auto jsonText = getText(column);
        if (jsonText.length == 0)
        {
            return Json.emptyObject;
        }
        try
        {
            return parseJsonString(jsonText);
        }
        catch (JSONException e)
        {
            throw new SQLiteException("Invalid JSON in column " ~ column.to!string ~ ": " ~ e.msg, 0);
        }
    }

    double getDouble(int column)
    {
        return sqlite3_column_double(stmt.stmt, column);
    }

    bool isNull(int column)
    {
        return sqlite3_column_type(stmt.stmt, column) == SQLITE_NULL;
    }

    int columnCount()
    {
        return sqlite3_column_count(stmt.stmt);
    }

    string columnName(int column)
    {
        auto cstr = sqlite3_column_name(stmt.stmt, column);
        return cstr ? to!string(cstr) : "";
    }

    auto front()
    {
        return this;
    }
}

struct Transaction
{
    private Database* db;
    private bool committed;

    this(ref Database database)
    {
        db = &database;
        db.execute("BEGIN");
    }

    ~this()
    {
        if (!committed)
        {
            rollback();
        }
    }

    void commit()
    {
        db.execute("COMMIT");
        committed = true;
    }

    void rollback()
    {
        if (!committed)
        {
            db.execute("ROLLBACK");
        }
    }
}

// Test cases
unittest
{
    import std.stdio;
    import std.file;
    import std.path;

    auto testDbPath = buildPath(tempDir(), "test_basic.db");
    scope (exit)
        if (exists(testDbPath))
            remove(testDbPath);

    auto db = Database(testDbPath);
    db.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, age INTEGER)");
    auto stmt = db.prepare("INSERT INTO users (name, age) VALUES (?, ?)");
    stmt.bind(1, "Alice");
    stmt.bind(2, 30);
    stmt.execute();
    stmt.bind(1, "Bob");
    stmt.bind(2, 25);
    stmt.execute();
    auto query = db.prepare("SELECT COUNT(*) FROM users WHERE age > ?");
    query.bind(1, 20);
    auto results = query.query();
    assert(results.getInt(0) == 2);
}

unittest
{
    import std.exception;

    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (id INTEGER, value TEXT)");
    {
        auto t = Transaction(db);
        db.execute("INSERT INTO test VALUES (1, 'test')");
        t.commit();
    }
    {
        auto t = Transaction(db);
        db.execute("INSERT INTO test VALUES (2, 'test2')");
    }
    auto stmt = db.prepare("SELECT COUNT(*) FROM test");
    assert(stmt.query().getInt(0) == 1); // Only committed row exists
    assertThrown!SQLiteException(db.execute("INVALID SQL"));
}

unittest
{
    auto db = Database(":memory:");
    db.execute(
        "CREATE TABLE types (int_col INTEGER, text_col TEXT, real_col REAL, null_col INTEGER)");
    auto stmt = db.prepare("INSERT INTO types VALUES (?, ?, ?, ?)");
    stmt.bind(1, 42);
    stmt.bind(2, "Hello 世界 🌍");
    stmt.bind(3, 3.14);
    stmt.bindNull(4);
    stmt.execute();
    auto query = db.prepare("SELECT * FROM types");
    auto results = query.query();
    assert(results.getInt(0) == 42);
    assert(results.getText(1) == "Hello 世界 🌍");
    assert(results.getDouble(2) == 3.14);
    assert(results.isNull(3));
}

unittest
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE json_test (id INTEGER, data JSON)");
    string jsonData = `{"name": "test", "value": 42, "active": true, "items": [1,2,3]}`;
    auto stmt = db.prepare("INSERT INTO json_test VALUES (?, ?)");
    stmt.bind(1, 1);
    stmt.bind(2, jsonData);
    stmt.execute();
    auto query = db.prepare("SELECT data FROM json_test WHERE id = 1");
    auto json = query.query().getJson(0);
    assert(json["name"].get!string == "test");
    assert(json["value"].get!int == 42);
    assert(json["items"].length == 3);
    db.execute("UPDATE json_test SET data = json_set(data, '$.value', 100) WHERE id = 1");
    auto updated = db.prepare("SELECT data FROM json_test WHERE id = 1").query().getJson(0);
    assert(updated["value"].get!int == 100);
}

class TestLogger : Logger
{
    string[] infoMessages;
    string[] warningMessages;
    string[] errorMessages;

    this()
    {
        super(LogLevel.all);
    }

    override void writeLogMsg(ref LogEntry payload) @trusted
    {
        string msg = payload.msg;
        final switch (payload.logLevel)
        {
        case LogLevel.info:
            infoMessages ~= msg;
            break;
        case LogLevel.warning:
            warningMessages ~= msg;
            break;
        case LogLevel.error:
            errorMessages ~= msg;
            break;
        case LogLevel.trace:
        case LogLevel.fatal:
        case LogLevel.all:
        case LogLevel.off:
        case LogLevel.critical:
            break;
        }
    }

    bool hasInfoMessage(string needle)
    {
        import std.algorithm : canFind;

        return infoMessages.canFind!(msg => msg.canFind(needle));
    }

    bool hasWarningMessage(string needle)
    {
        import std.algorithm : canFind;

        return warningMessages.canFind!(msg => msg.canFind(needle));
    }

    void clear()
    {
        infoMessages.length = 0;
        warningMessages.length = 0;
        errorMessages.length = 0;
    }

    size_t totalMessages()
    {
        return infoMessages.length + warningMessages.length + errorMessages.length;
    }
}

unittest
{
    import std.file;
    import std.path;
    import core.thread;
    import core.time;

    auto testLogger = new TestLogger();
    auto testDbPath = buildPath(tempDir(), "test_callback.db");
    scope (exit)
    {
        if (exists(testDbPath))
        {
            remove(testDbPath);
        }
    }
    auto db = Database(testDbPath, testLogger);
    Thread.sleep(10.msecs);
    db.execute("CREATE TABLE test_logging (id INTEGER, value TEXT)");
    auto stmt = db.prepare("INSERT INTO test_logging VALUES (?, ?)");
    stmt.bind(1, 1);
    stmt.bind(2, "test value");
    stmt.execute();
    writefln("Total messages logged: %d", testLogger.totalMessages());
    writefln("Info messages: %s", testLogger.infoMessages);
    writefln("Warning messages: %s", testLogger.warningMessages);
}
