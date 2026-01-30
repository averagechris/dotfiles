import { readFileSync } from "fs";

export default function (api: any) {
  api.registerTool({
    name: "kagi_search",
    description: "Search the web using Kagi Search API. Provides high-quality, ad-free search results.",
    schema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Search query string"
        },
        limit: {
          type: "number",
          description: "Number of results to return (1-10)",
          minimum: 1,
          maximum: 10
        }
      },
      required: ["query"]
    },
    handler: async ({ query, limit = 5 }: { query: string; limit?: number }, ctx: any) => {
      // Try to get API token from plugin config first, then fall back to agenix secret
      let apiToken = ctx.getPluginConfig?.("kagi-search")?.apiToken;
      
      if (!apiToken) {
        try {
          apiToken = readFileSync("/run/agenix/kagi-api-token", "utf-8").trim();
        } catch (e) {
          return {
            error: "Kagi API token not available. Check /run/agenix/kagi-api-token"
          };
        }
      }

      try {
        const response = await fetch("https://kagi.com/api/v0/search", {
          method: "POST",
          headers: {
            "Authorization": `Bot ${apiToken}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            q: query,
            limit: Math.min(limit, 10)
          })
        });

        if (!response.ok) {
          const errorText = await response.text();
          return {
            error: `Kagi API error (${response.status}): ${errorText}`
          };
        }

        const data = await response.json();
        
        if (!data.data || !Array.isArray(data.data)) {
          return { error: "Unexpected response format from Kagi API", raw: data };
        }

        const results = data.data.map((result: any) => ({
          title: result.title || "No title",
          url: result.url || "",
          snippet: result.snippet || ""
        }));

        return {
          query,
          count: results.length,
          results
        };

      } catch (error: any) {
        return { error: `Kagi search failed: ${error.message}` };
      }
    }
  });
}
