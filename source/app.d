import hnclient;
import sqlite_wrapper;
import std.stdio;
import std.getopt;
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

void main(string[] args)
{
    string database = "hackernews.sqlite";
    auto helpInformation = getopt(args, "database", &database);
    if (helpInformation.helpWanted)
    {
        defaultGetoptPrinter("Some information about the program.", helpInformation.options);
    }
    auto db = Database(database);
    db.create_tables(true);
    auto itemId = latestItemId();
    auto item = getItem(itemId);
    db.upsert_item(item);
}
