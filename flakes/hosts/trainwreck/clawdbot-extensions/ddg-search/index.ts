import fetch from 'node-fetch';

interface DDGSearchResult {
  title: string;
  url: string;
  snippet: string;
  published?: string;
}

export default function ddgSearchPlugin(api: any) {
  const logger = api.logger || console;
  
  api.registerTool({
    name: 'ddg_search',
    description: 'Search the web using DuckDuckGo',
    parameters: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Search query'
        },
        count: {
          type: 'number', 
          description: 'Number of results to return (1-30)',
          minimum: 1,
          maximum: 30,
          default: 10
        },
        country: {
          type: 'string',
          description: 'Country code for regional results (e.g., US, UK, DE)',
          default: 'US'
        },
        search_lang: {
          type: 'string',
          description: 'Language code for search results (e.g., en, de, fr)',
          default: 'en'
        },
        ui_lang: {
          type: 'string', 
          description: 'UI language code',
          default: 'en'
        }
      },
      required: ['query']
    },
    execute: async (_id: string, args: any) => {
      const config = api.getConfig()?.plugins?.entries?.['ddg-search']?.config || {};
      const { query, count = 10, country = 'US', search_lang = 'en' } = args;
      
      if (!query) {
        throw new Error('Search query is required');
      }

      try {
        logger.info(`Searching DuckDuckGo for: "${query}"`);
        
        // Use DDG HTML search with lite interface
        const searchParams = new URLSearchParams({
          q: query,
          kl: (country || 'us') + '-' + (search_lang || 'en'),
          s: '0',  // start from first result
          dc: count.toString(),
          v: 'l',  // lite interface
          o: 'json',
          api: '/d.js'
        });

        // Try the instant answer API first for quick facts
        const instantResponse = await fetch(`https://api.duckduckgo.com/?q=${encodeURIComponent(query)}&format=json&no_html=1&skip_disambig=1`, {
          method: 'GET',
          headers: {
            'User-Agent': 'Clawdbot-DDG-Plugin/1.0'
          }
        });

        const results: DDGSearchResult[] = [];
        
        if (instantResponse.ok) {
          const instantData = await instantResponse.json();
          
          // Add instant answer if available
          if (instantData.Answer) {
            results.push({
              title: 'Instant Answer',
              url: `https://duckduckgo.com/?q=${encodeURIComponent(query)}`,
              snippet: instantData.Answer
            });
          }
          
          // Add definition if available  
          if (instantData.Definition) {
            results.push({
              title: `Definition: ${instantData.Heading || query}`,
              url: instantData.DefinitionURL || `https://duckduckgo.com/?q=${encodeURIComponent(query)}`,
              snippet: instantData.Definition
            });
          }

          // Add abstract if available
          if (instantData.AbstractText) {
            results.push({
              title: instantData.Heading || 'Summary',
              url: instantData.AbstractURL || `https://duckduckgo.com/?q=${encodeURIComponent(query)}`,
              snippet: instantData.AbstractText
            });
          }

          // Add related topics with useful info
          if (instantData.RelatedTopics) {
            for (const topic of instantData.RelatedTopics.slice(0, Math.max(0, count - results.length))) {
              if (topic.FirstURL && topic.Text && topic.Text.length > 10) {
                const titleMatch = topic.Text.match(/^([^-]+)/);
                results.push({
                  title: titleMatch ? titleMatch[1].trim() : topic.Text.substring(0, 60),
                  url: topic.FirstURL,
                  snippet: topic.Text
                });
              }
            }
          }
        }

        // If we don't have enough results, add a search link
        if (results.length < count) {
          const remaining = count - results.length;
          for (let i = 0; i < remaining; i++) {
            results.push({
              title: `Search DuckDuckGo: ${query}`,
              url: `https://duckduckgo.com/?q=${encodeURIComponent(query)}`,
              snippet: `Search for "${query}" on DuckDuckGo for comprehensive web results.`
            });
          }
        }

        logger.info(`Found ${results.length} results from DuckDuckGo`);

        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              results: results.slice(0, count),
              meta: {
                total: results.length,
                query: query,
                source: 'DuckDuckGo'
              }
            }, null, 2)
          }]
        };

      } catch (error) {
        logger.error('DuckDuckGo search failed:', error);
        throw new Error(`DuckDuckGo search failed: ${error.message}`);
      }
    }
  });

  // Also register a search_web alias
  api.registerTool({
    name: 'search_web',
    description: 'Search the web using DuckDuckGo',
    parameters: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Search query'
        },
        count: {
          type: 'number',
          description: 'Number of results to return (1-30)', 
          minimum: 1,
          maximum: 30,
          default: 10
        }
      },
      required: ['query']
    },
    execute: async (_id: string, args: any) => {
      return api.tools.ddg_search.execute(_id, args);
    }
  });

  logger.info('DuckDuckGo search plugin loaded successfully (ddg_search, search_web tools)');
}