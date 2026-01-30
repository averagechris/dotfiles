import { readFileSync } from "fs";

export default function (api: any) {
  api.registerTool({
    name: "kagi_search",
    description: "Search the web using Kagi Search API. Provides high-quality, ad-free search results.",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Search query string"
        },
        limit: {
          type: "number",
          description: "Number of results to return (1-20)"
        }
      },
      required: ["query"]
    },
    execute: async (_toolCallId: string, args: any) => {
      const query = args.query;
      const limit = args.limit ?? 10;
      
      // Read API token from agenix secret
      let apiToken: string;
      try {
        apiToken = readFileSync("/run/agenix/kagi-api-token", "utf-8").trim();
      } catch (e) {
        return {
          content: [{ type: "text", text: "Error: Kagi API token not available. Check /run/agenix/kagi-api-token" }]
        };
      }

      try {
        // Kagi API uses GET with query params
        const url = new URL("https://kagi.com/api/v0/search");
        url.searchParams.set("q", query);
        if (limit) {
          url.searchParams.set("limit", String(Math.min(limit, 20)));
        }

        const response = await fetch(url.toString(), {
          method: "GET",
          headers: {
            "Authorization": `Bot ${apiToken}`
          }
        });

        if (!response.ok) {
          const errorText = await response.text();
          return {
            content: [{ type: "text", text: `Kagi API error (${response.status}): ${errorText.slice(0, 200)}` }]
          };
        }

        const data = await response.json();
        
        if (!data.data || !Array.isArray(data.data)) {
          return {
            content: [{ type: "text", text: "Unexpected response format from Kagi API" }]
          };
        }

        // Filter for search results (t=0) and format them
        const results = data.data
          .filter((item: any) => item.t === 0)
          .slice(0, limit)
          .map((result: any) => ({
            title: result.title || "No title",
            url: result.url || "",
            snippet: result.snippet || "",
            published: result.published || null
          }));

        const payload = { 
          query, 
          count: results.length, 
          results,
          api_balance: data.meta?.api_balance
        };

        // Return in openclaw's expected format
        return {
          content: [{ type: "text", text: JSON.stringify(payload, null, 2) }],
          details: payload
        };

      } catch (error: any) {
        return {
          content: [{ type: "text", text: `Kagi search failed: ${error.message}` }]
        };
      }
    }
  });
}
