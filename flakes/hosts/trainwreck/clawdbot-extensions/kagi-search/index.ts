import fetch from 'node-fetch';

interface KagiSearchResult {
  title: string;
  url: string;
  snippet: string;
  published?: string;
  thumbnail?: string;
}

interface KagiApiResponse {
  meta: {
    id: string;
    node: string;
    ms: number;
  };
  data: Array<{
    t: number; // result type
    u: string; // url
    title: string;
    snippet: string;
    published?: string;
    thumbnail?: {
      url: string;
      height: number;
      width: number;
    };
  }>;
}

export default function kagiSearchPlugin(api: any) {
  const logger = api.logger.child({ plugin: 'kagi-search' });
  
  api.registerTool({
    name: 'kagi_search',
    description: 'Search the web using Kagi for high-quality results',
    parameters: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Search query'
        },
        count: {
          type: 'number',
          description: 'Number of results to return (1-50)',
          minimum: 1,
          maximum: 50,
          default: 10
        },
        safeSearch: {
          type: 'string',
          enum: ['off', 'moderate', 'strict'],
          description: 'Safe search setting',
          default: 'moderate'
        }
      },
      required: ['query']
    },
    handler: async (args: any, context: any) => {
      const config = api.getConfig()?.plugins?.entries?.['kagi-search']?.config;
      
      if (!config?.apiToken) {
        throw new Error('Kagi API token not configured. Please set plugins.entries.kagi-search.config.apiToken');
      }

      const { query, count = 10, safeSearch = 'moderate' } = args;
      
      if (!query) {
        throw new Error('Search query is required');
      }

      try {
        logger.info(`Searching Kagi for: "${query}"`);
        
        const searchParams = new URLSearchParams({
          q: query,
          limit: count.toString(),
          safesearch: safeSearch
        });

        const response = await fetch(`https://kagi.com/api/v0/search?${searchParams}`, {
          method: 'GET',
          headers: {
            'Authorization': `Bot ${config.apiToken}`,
            'User-Agent': 'Clawdbot-Kagi-Plugin/1.0'
          }
        });

        if (!response.ok) {
          const errorText = await response.text();
          throw new Error(`Kagi API error (${response.status}): ${errorText}`);
        }

        const data: KagiApiResponse = await response.json();
        
        const results: KagiSearchResult[] = data.data
          .filter(item => item.t === 0) // Filter for web results (t=0)
          .map(item => ({
            title: item.title,
            url: item.u,
            snippet: item.snippet,
            published: item.published,
            thumbnail: item.thumbnail?.url
          }));

        logger.info(`Found ${results.length} results from Kagi`);

        return {
          success: true,
          results,
          meta: {
            total: results.length,
            query: query,
            searchTime: data.meta.ms
          }
        };

      } catch (error) {
        logger.error('Kagi search failed:', error);
        throw new Error(`Kagi search failed: ${error.message}`);
      }
    }
  });

  // Also register as a replacement for web_search if desired
  api.registerGatewayMethod('web_search_kagi', async ({ respond, body }) => {
    try {
      const { query, count = 10, safeSearch = 'moderate' } = body;
      
      const result = await api.tools.kagi_search.handler({ query, count, safeSearch }, {});
      
      respond(true, {
        results: result.results.map((r: KagiSearchResult) => ({
          title: r.title,
          url: r.url,
          snippet: r.snippet,
          published: r.published
        })),
        meta: result.meta
      });
    } catch (error) {
      respond(false, { error: error.message });
    }
  });

  logger.info('Kagi search plugin loaded successfully');
}