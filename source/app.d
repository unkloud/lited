import hnclient;
import sqlite_wrapper;
import std.getopt;
import std.logger;
import std.stdio;
import vibe.data.json;

void create_tables(ref Database db, bool drop_first = false)
{
    if (drop_first)
    {
        db.execute("drop index if exists idx_hackernews_items_id;");
        db.execute("drop table if exists hackernews_items;");
    }
    db.execute(`
    CREATE TABLE if not exists hackernews_items (
        id INTEGER PRIMARY KEY NOT NULL,
        content JSON);
    CREATE INDEX if not exists idx_hackernews_items_id ON hackernews_items(id);
    `);
}

void upsert_item(ref Database db, in ref HNItem item)
{
    if (item.content != Json.emptyObject)
    {
        auto stmt = db.prepare(
            "INSERT OR REPLACE INTO hackernews_items (id, content) VALUES (?, ?)");
        stmt.bind(1, item.id);
        stmt.bind(2, item.content);
        stmt.execute();
    }
}

bool itemRecored(ref Database db, ulong itemId)
{
    auto stmt = db.prepare("select * from hackernews_items where id=?");
    stmt.bind(1, itemId);
    auto rs = stmt.query();
    return !rs.empty;
}

ulong minRecordedId(ref Database db)
{
    auto sql = "select min(id) from hackernews_items";
    auto stmt = db.prepare(sql);
    auto rs = stmt.query();
    while (!rs.empty)
    {
        return rs.getInt(0);
    }
    return -1;
}

enum CrawlStartPoint
{
    LatestOnline,
    LatestRecorded
}

void crawlBack(ref Database db, ulong startPoint, ulong count)
{
    for (ulong i = startPoint; startPoint - i < count; i--)
    {
        if (!db.itemRecored(i))
        {
            auto item = getItem(i);
            db.upsert_item(item);
        }
    }
}

void main(string[] args)
{
    string database = "hackernews.sqlite";
    string logPath = "app.log";
    bool recreateDB = false;
    CrawlStartPoint startPoint = CrawlStartPoint.LatestRecorded;
    int stopCount = -1;
    auto helpInformation = getopt(args,
        "database", &database,
        "logPath", &logPath,
        "recreateDB", &recreateDB,
        "startPoint", &startPoint,
        "stopCount", &stopCount);
    if (helpInformation.helpWanted)
    {
        defaultGetoptPrinter("Hacker News Crawler", helpInformation.options);
        return;
    }
    auto logger = new FileLogger(logPath);
    auto db = Database(database, logger);
    db.create_tables(recreateDB);
    assert(startPoint == CrawlStartPoint.LatestOnline || startPoint == CrawlStartPoint
            .LatestRecorded);
    long startId = startPoint == CrawlStartPoint.LatestOnline ? latestItemId() : db.minRecordedId();
    ulong count = stopCount == -1 ? startId : stopCount;
    db.crawlBack(startId, count);
}
