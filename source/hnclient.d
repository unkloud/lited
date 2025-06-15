module hnclient;
import vibe.core.log;
import vibe.http.client;
import vibe.stream.operations;
import vibe.data.json;
import std.conv : text;
import std.stdio;

enum UA_STR = "Mozilla/5.0 (X11; Linux x86_64; rv:139.0) Gecko/20100101 Firefox/139.0";
enum ENDPOINT_HOST = "https://hacker-news.firebaseio.com";
enum LATEST_ITEM_ID_ENDPOINT = ENDPOINT_HOST ~ "/v0/maxitem.json";

struct HNItem
{
    ulong id;
    Json content;
}

Json fetchJson(string endpoint)
{
    Json retVal = Json.emptyObject;
    try
    {
        requestHTTP(endpoint, (scope req) {
            req.method = HTTPMethod.GET;
            req.headers["User-Agent"] = UA_STR;
        }, (scope resp) {
            auto jsonStr = resp.bodyReader.readAllUTF8();
            auto jsonValue = parseJsonString(jsonStr);
            retVal = jsonValue;
        });
    }
    catch (Exception e)
    {
        logError("Error fetching JSON: %s", e.msg);
    }
    return retVal;
}

ulong latestItemId()
{
    auto r = fetchJson(LATEST_ITEM_ID_ENDPOINT);
    return r.get!ulong;
}

HNItem getItem(ulong itemId)
{
    auto itemUri = i"$(ENDPOINT_HOST)/v0/item/$(itemId).json".text;
    auto JsonItem = fetchJson(itemUri);
    return HNItem(itemId, JsonItem);
}
