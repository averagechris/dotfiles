import { readFileSync } from "fs";

// Popular meme templates with their IDs
const POPULAR_TEMPLATES = [
  { id: "181913649", name: "Drake Pointing", description: "Drake pointing and approving" },
  { id: "87743020", name: "Two Buttons", description: "Person sweating over two button choices" },
  { id: "112126428", name: "Distracted Boyfriend", description: "Man looking at another woman while girlfriend looks annoyed" },
  { id: "131087935", name: "Running Away Balloon", description: "Person reaching for floating balloon" },
  { id: "4087833", name: "Waiting Skeleton", description: "Skeleton sitting and waiting" },
  { id: "222403160", name: "Bernie I Am Once Again Asking For Your Support", description: "Bernie Sanders asking for support" },
  { id: "438680", name: "Batman Slapping Robin", description: "Batman slapping Robin" },
  { id: "124822590", name: "Left Exit 12 Off Ramp", description: "Car choosing between highway and exit" },
  { id: "161865971", name: "Marked Safe From", description: "Facebook 'marked safe' template" },
  { id: "119139145", name: "Blank Nut Button", description: "Hand hovering over red button" },
  { id: "155067746", name: "Surprised Pikachu", description: "Pikachu with surprised expression" },
  { id: "217743513", name: "UNO Draw 25 Cards", description: "UNO player choosing between action and drawing cards" },
  { id: "91538330", name: "X, X Everywhere", description: "Buzz and Woody 'X everywhere' meme" },
  { id: "101470", name: "Ancient Aliens", description: "Giorgio Tsoukalos 'aliens' gesture" },
  { id: "123999232", name: "The Scroll Of Truth", description: "Person reading scroll and throwing it away" }
];

export default function (api: any) {
  
  // Helper function to get OpenRouter API key
  function getOpenRouterKey(): string | null {
    try {
      return readFileSync("/run/agenix/openrouter-api-key", "utf-8").trim();
    } catch (e) {
      return api.config?.openrouterApiKey || null;
    }
  }

  // Register list templates tool
  api.registerTool({
    name: "meme_list_templates",
    description: "List popular meme templates available for generation",
    parameters: {
      type: "object",
      properties: {},
      required: []
    },
    execute: async (_toolCallId: string, args: any) => {
      const templateList = POPULAR_TEMPLATES.map(t => 
        `${t.name} (ID: ${t.id}) - ${t.description}`
      ).join('\n');
      
      return {
        content: [{ 
          type: "text", 
          text: `Popular Meme Templates:\n\n${templateList}\n\nUse meme_generate with a template_id to create a meme, or use meme_generate_ai for AI-generated meme images.`
        }],
        details: { templates: POPULAR_TEMPLATES }
      };
    }
  });

  // Register traditional meme generation tool
  api.registerTool({
    name: "meme_generate",
    description: "Generate a meme using a popular template with custom text",
    parameters: {
      type: "object",
      properties: {
        template_id: {
          type: "string",
          description: "Template ID from the popular templates list, or search for custom template"
        },
        top_text: {
          type: "string",
          description: "Text for the top of the meme"
        },
        bottom_text: {
          type: "string",
          description: "Text for the bottom of the meme",
          default: ""
        },
        search_template: {
          type: "string",
          description: "Search for a template by name if template_id not provided"
        }
      },
      required: []
    },
    execute: async (_toolCallId: string, args: any) => {
      try {
        let templateId = args.template_id;
        
        // If no template_id provided but search_template is, search for it
        if (!templateId && args.search_template) {
          try {
            const searchUrl = `https://api.imgflip.com/get_memes`;
            const searchResponse = await fetch(searchUrl);
            const searchData = await searchResponse.json();
            
            if (searchData.success && searchData.data.memes) {
              const found = searchData.data.memes.find((meme: any) => 
                meme.name.toLowerCase().includes(args.search_template.toLowerCase())
              );
              if (found) {
                templateId = found.id;
              } else {
                return {
                  content: [{ type: "text", text: `No template found matching "${args.search_template}". Try using meme_list_templates to see popular options.` }]
                };
              }
            }
          } catch (searchError: any) {
            return {
              content: [{ type: "text", text: `Error searching templates: ${searchError.message}` }]
            };
          }
        }
        
        // Default to Drake template if nothing specified
        if (!templateId) {
          templateId = "181913649"; // Drake Pointing
        }
        
        const topText = args.top_text || "";
        const bottomText = args.bottom_text || "";
        
        if (!topText && !bottomText) {
          return {
            content: [{ type: "text", text: "Please provide at least top_text or bottom_text for the meme." }]
          };
        }

        // Build form data
        const formData = new URLSearchParams();
        formData.append('template_id', templateId);
        formData.append('text0', topText);
        formData.append('text1', bottomText);
        
        // Add username/password if configured
        const imgflipUsername = api.config?.imgflipUsername;
        const imgflipPassword = api.config?.imgflipPassword;
        
        if (imgflipUsername && imgflipPassword) {
          formData.append('username', imgflipUsername);
          formData.append('password', imgflipPassword);
        }

        const response = await fetch('https://api.imgflip.com/caption_image', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: formData
        });

        const data = await response.json();
        
        if (!data.success) {
          const errorMsg = data.error_message || 'Unknown error';
          if (errorMsg.includes('Username and password')) {
            return {
              content: [{ 
                type: "text", 
                text: `⚠️ Imgflip now requires authentication for meme templates.\n\n**Options:**\n1. **Use AI memes**: Try \`meme_generate_ai\` for custom meme images\n2. **Configure Imgflip**: Add credentials to plugin config:\n   \`\`\`\n   imgflipUsername: "your_username"\n   imgflipPassword: "your_password"\n   \`\`\`\n\n**For now, try AI memes instead!** 🎨\n\nError: ${errorMsg}` 
              }]
            };
          }
          return {
            content: [{ type: "text", text: `Imgflip API error: ${errorMsg}` }]
          };
        }

        const template = POPULAR_TEMPLATES.find(t => t.id === templateId);
        const templateName = template?.name || `Template ${templateId}`;
        
        return {
          content: [{ 
            type: "text", 
            text: `✅ Meme generated successfully!\n\n**Template:** ${templateName}\n**Top text:** ${topText}\n**Bottom text:** ${bottomText}\n\n**Meme URL:** ${data.data.url}` 
          }],
          details: {
            success: true,
            template_id: templateId,
            template_name: templateName,
            top_text: topText,
            bottom_text: bottomText,
            url: data.data.url,
            page_url: data.data.page_url
          }
        };

      } catch (error: any) {
        return {
          content: [{ type: "text", text: `Meme generation failed: ${error.message}` }]
        };
      }
    }
  });

  // Register AI meme generation tool
  api.registerTool({
    name: "meme_generate_ai",
    description: "Generate a meme using AI image generation (requires OpenRouter API key)",
    parameters: {
      type: "object",
      properties: {
        prompt: {
          type: "string",
          description: "Description of the meme image to generate"
        },
        style: {
          type: "string",
          description: "Style of the meme (funny, absurd, clever, etc.)",
          default: "funny"
        },
        model: {
          type: "string",
          description: "AI model to use for generation. Nano Banana models are Google's image generators.",
          default: "google/gemini-2.5-flash-image",
          enum: [
            "google/gemini-2.5-flash-image",
            "google/gemini-3-pro-image-preview",
            "openai/gpt-5-image-mini",
            "openai/gpt-5-image"
          ]
        }
      },
      required: ["prompt"]
    },
    execute: async (_toolCallId: string, args: any) => {
      const openrouterKey = getOpenRouterKey();
      
      if (!openrouterKey) {
        return {
          content: [{ 
            type: "text", 
            text: "❌ OpenRouter API key not configured. Cannot generate AI memes.\n\nSet up the API key in your config or use traditional memes with meme_generate instead." 
          }]
        };
      }

      try {
        const prompt = args.prompt;
        const style = args.style || "funny";
        const model = args.model || "google/gemini-2.5-flash-image";
        
        // Enhance the prompt for meme generation
        const enhancedPrompt = `${prompt}, ${style} meme style, internet meme format, high quality, clear text readability, meme aesthetic`;

        // Use OpenRouter's image generation API with the chat completions endpoint
        const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${openrouterKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model: model,
            messages: [
              {
                role: "user", 
                content: enhancedPrompt
              }
            ],
            modalities: ["image", "text"]
          })
        });

        if (!response.ok) {
          const errorData = await response.text();
          return {
            content: [{ type: "text", text: `OpenRouter API error (${response.status}): ${errorData}` }]
          };
        }

        const data = await response.json();
        
        if (!data.choices || !data.choices[0] || !data.choices[0].message || !data.choices[0].message.images) {
          return {
            content: [{ type: "text", text: "Unexpected response format from OpenRouter API. Model may not support image generation." }]
          };
        }

        const images = data.choices[0].message.images;
        if (!images || images.length === 0) {
          return {
            content: [{ type: "text", text: "No images generated. Make sure the model supports image generation." }]
          };
        }

        const imageData = images[0].image_url.url;
        
        // Check if it's a base64 data URL
        const isBase64 = imageData.startsWith('data:image/');
        
        // Build content array with proper moltbot image format
        const contentItems: any[] = [{ 
          type: "text", 
          text: `🎨 AI Meme generated successfully!\n\n**Prompt:** ${prompt}\n**Style:** ${style}\n**Model:** ${model}` 
        }];
        
        if (isBase64) {
          // Extract media type and base64 data from data URL
          // Format: data:image/png;base64,iVBORw0KGgo...
          const matches = imageData.match(/^data:(image\/[^;]+);base64,(.+)$/);
          if (matches) {
            const [, mediaType, base64Data] = matches;
            // Use moltbot's expected format for base64 images
            contentItems.push({
              type: "image",
              source: {
                type: "base64",
                media_type: mediaType,
                data: base64Data
              }
            });
          } else {
            // Fallback: include as image_url with full data URL
            contentItems.push({
              type: "image_url",
              image_url: { url: imageData }
            });
          }
        } else {
          // Regular URL - use image_url format
          contentItems.push({
            type: "image_url",
            image_url: { url: imageData }
          });
        }
        
        return {
          content: contentItems,
          details: {
            success: true,
            prompt: prompt,
            enhanced_prompt: enhancedPrompt,
            style: style,
            model: model,
            image_data: imageData,
            is_base64: isBase64
          }
        };

      } catch (error: any) {
        return {
          content: [{ type: "text", text: `AI meme generation failed: ${error.message}` }]
        };
      }
    }
  });

  // Register meme search tool
  api.registerTool({
    name: "meme_search_templates",
    description: "Search for meme templates by keyword",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Search term for finding meme templates"
        },
        limit: {
          type: "number",
          description: "Maximum number of results to return",
          default: 10
        }
      },
      required: ["query"]
    },
    execute: async (_toolCallId: string, args: any) => {
      try {
        const response = await fetch('https://api.imgflip.com/get_memes');
        const data = await response.json();
        
        if (!data.success) {
          return {
            content: [{ type: "text", text: `Error fetching meme templates: ${data.error_message || 'Unknown error'}` }]
          };
        }

        const query = args.query.toLowerCase();
        const limit = args.limit || 10;
        
        const matchingMemes = data.data.memes
          .filter((meme: any) => meme.name.toLowerCase().includes(query))
          .slice(0, limit)
          .map((meme: any) => ({
            id: meme.id,
            name: meme.name,
            url: meme.url,
            width: meme.width,
            height: meme.height,
            box_count: meme.box_count
          }));

        if (matchingMemes.length === 0) {
          return {
            content: [{ type: "text", text: `No meme templates found matching "${args.query}". Try a different search term.` }]
          };
        }

        const resultText = matchingMemes
          .map(meme => `**${meme.name}** (ID: ${meme.id}) - ${meme.width}x${meme.height}, ${meme.box_count} text boxes`)
          .join('\n');
        
        return {
          content: [{ 
            type: "text", 
            text: `Found ${matchingMemes.length} meme templates for "${args.query}":\n\n${resultText}\n\nUse the ID with meme_generate to create a meme.`
          }],
          details: { 
            query: args.query, 
            count: matchingMemes.length, 
            results: matchingMemes 
          }
        };

      } catch (error: any) {
        return {
          content: [{ type: "text", text: `Meme search failed: ${error.message}` }]
        };
      }
    }
  });
}