import { readFileSync } from "fs";

// Preset styles for common use cases
const IMAGE_STYLES = [
  { id: "avatar", name: "Avatar/Profile Pic", description: "Clean, centered portrait suitable for profile pictures" },
  { id: "artistic", name: "Artistic", description: "Creative, painterly style with artistic flair" },
  { id: "photorealistic", name: "Photorealistic", description: "Realistic, photo-like quality" },
  { id: "cartoon", name: "Cartoon", description: "Fun, animated cartoon style" },
  { id: "pixel-art", name: "Pixel Art", description: "Retro pixel art aesthetic" },
  { id: "minimalist", name: "Minimalist", description: "Simple, clean, minimal design" },
  { id: "cyberpunk", name: "Cyberpunk", description: "Neon-lit, futuristic cyberpunk aesthetic" },
  { id: "watercolor", name: "Watercolor", description: "Soft, flowing watercolor painting style" },
  { id: "sketch", name: "Sketch", description: "Hand-drawn pencil sketch style" },
  { id: "anime", name: "Anime", description: "Japanese anime/manga art style" }
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

  // Register list styles tool
  api.registerTool({
    name: "image_list_styles",
    description: "List available image styles/presets for generation",
    parameters: {
      type: "object",
      properties: {},
      required: []
    },
    execute: async (_toolCallId: string, _args: any) => {
      const styleList = IMAGE_STYLES.map(s => 
        `**${s.name}** (${s.id}) - ${s.description}`
      ).join('\n');
      
      return {
        content: [{ 
          type: "text", 
          text: `Available Image Styles:\n\n${styleList}\n\nUse image_generate with a style parameter, or describe your own custom style in the prompt.`
        }],
        details: { styles: IMAGE_STYLES }
      };
    }
  });

  // Register main image generation tool
  api.registerTool({
    name: "image_generate",
    description: "Generate an image using AI. Great for profile pics, avatars, artwork, illustrations, or any visual content.",
    parameters: {
      type: "object",
      properties: {
        prompt: {
          type: "string",
          description: "Description of the image to generate. Be specific about subject, composition, colors, mood, etc."
        },
        style: {
          type: "string",
          description: "Style preset (avatar, artistic, photorealistic, cartoon, pixel-art, minimalist, cyberpunk, watercolor, sketch, anime) or custom style description",
          default: "artistic"
        },
        aspect_ratio: {
          type: "string",
          description: "Aspect ratio hint for the image",
          default: "square",
          enum: ["square", "portrait", "landscape", "wide"]
        },
        model: {
          type: "string",
          description: "AI model to use for generation",
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
            text: "OpenRouter API key not configured. Cannot generate images.\n\nSet up the API key in your config or via agenix secrets." 
          }]
        };
      }

      try {
        const prompt = args.prompt;
        const styleInput = args.style || "artistic";
        const aspectRatio = args.aspect_ratio || "square";
        const model = args.model || "google/gemini-2.5-flash-image";
        
        // Look up style preset or use custom style
        const stylePreset = IMAGE_STYLES.find(s => s.id === styleInput.toLowerCase());
        const styleDescription = stylePreset ? stylePreset.name.toLowerCase() + " style" : styleInput;
        
        // Build aspect ratio hint
        const aspectHints: Record<string, string> = {
          "square": "square composition, 1:1 aspect ratio",
          "portrait": "vertical portrait composition, taller than wide",
          "landscape": "horizontal landscape composition, wider than tall",
          "wide": "cinematic wide composition, ultrawide aspect ratio"
        };
        const aspectHint = aspectHints[aspectRatio] || aspectHints["square"];
        
        // Enhance the prompt for better results
        const enhancedPrompt = `${prompt}, ${styleDescription}, ${aspectHint}, high quality, detailed`;

        // Use OpenRouter's image generation API
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
        
        // For base64 images, save to a temp file
        if (isBase64) {
          const fs = await import('fs');
          const path = await import('path');
          const os = await import('os');
          
          // Extract media type and base64 data
          const matches = imageData.match(/^data:(image\/([^;]+));base64,(.+)$/);
          if (matches) {
            const [, mediaType, extension, base64Data] = matches;
            const ext = extension === 'jpeg' ? 'jpg' : extension;
            
            // Save to temp file
            const tempDir = os.tmpdir();
            const filename = `image-${Date.now()}.${ext}`;
            const filepath = path.join(tempDir, filename);
            
            const buffer = Buffer.from(base64Data, 'base64');
            fs.writeFileSync(filepath, buffer);
            
            return {
              content: [{ 
                type: "text", 
                text: `Image generated successfully!\n\n**Prompt:** ${prompt}\n**Style:** ${stylePreset?.name || styleInput}\n**Aspect:** ${aspectRatio}\n**Model:** ${model}\n\n**Image saved to:** ${filepath}\n\nUse the message tool to send this image to the user.`
              }],
              details: {
                success: true,
                prompt: prompt,
                enhanced_prompt: enhancedPrompt,
                style: stylePreset?.name || styleInput,
                aspect_ratio: aspectRatio,
                model: model,
                image_path: filepath,
                media_type: mediaType
              }
            };
          }
        }
        
        // For regular URLs, just return the URL
        return {
          content: [{ 
            type: "text", 
            text: `Image generated successfully!\n\n**Prompt:** ${prompt}\n**Style:** ${stylePreset?.name || styleInput}\n**Aspect:** ${aspectRatio}\n**Model:** ${model}\n\n**Image URL:** ${imageData}`
          }],
          details: {
            success: true,
            prompt: prompt,
            enhanced_prompt: enhancedPrompt,
            style: stylePreset?.name || styleInput,
            aspect_ratio: aspectRatio,
            model: model,
            image_url: imageData
          }
        };

      } catch (error: any) {
        return {
          content: [{ type: "text", text: `Image generation failed: ${error.message}` }]
        };
      }
    }
  });

  // Register a quick profile pic generator
  api.registerTool({
    name: "image_profile_pic",
    description: "Generate a profile picture/avatar based on a mood, theme, or description. Optimized for profile pic use.",
    parameters: {
      type: "object",
      properties: {
        description: {
          type: "string",
          description: "What kind of profile pic you want (e.g., 'feeling energetic today', 'cozy autumn vibes', 'mysterious and cool')"
        },
        style: {
          type: "string",
          description: "Art style for the profile pic",
          default: "avatar",
          enum: ["avatar", "artistic", "cartoon", "pixel-art", "minimalist", "cyberpunk", "anime"]
        },
        subject: {
          type: "string",
          description: "Main subject of the profile pic (e.g., 'robot', 'cat', 'abstract shape', 'person silhouette')",
          default: "abstract character"
        },
        model: {
          type: "string",
          description: "AI model to use for generation",
          default: "google/gemini-2.5-flash-image",
          enum: [
            "google/gemini-2.5-flash-image",
            "google/gemini-3-pro-image-preview",
            "openai/gpt-5-image-mini",
            "openai/gpt-5-image"
          ]
        }
      },
      required: ["description"]
    },
    execute: async (_toolCallId: string, args: any) => {
      const openrouterKey = getOpenRouterKey();
      
      if (!openrouterKey) {
        return {
          content: [{ 
            type: "text", 
            text: "OpenRouter API key not configured. Cannot generate images." 
          }]
        };
      }

      try {
        const description = args.description;
        const style = args.style || "avatar";
        const subject = args.subject || "abstract character";
        const model = args.model || "google/gemini-2.5-flash-image";
        
        // Build an optimized profile pic prompt
        const stylePreset = IMAGE_STYLES.find(s => s.id === style);
        const styleDesc = stylePreset?.name.toLowerCase() || style;
        
        const enhancedPrompt = `Profile picture of ${subject}, ${description}, ${styleDesc} style, centered composition, square format, suitable for avatar use, clean background, high quality, visually striking`;

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
            content: [{ type: "text", text: "Unexpected response format. Model may not support image generation." }]
          };
        }

        const images = data.choices[0].message.images;
        if (!images || images.length === 0) {
          return {
            content: [{ type: "text", text: "No images generated." }]
          };
        }

        const imageData = images[0].image_url.url;
        const isBase64 = imageData.startsWith('data:image/');
        
        if (isBase64) {
          const fs = await import('fs');
          const path = await import('path');
          const os = await import('os');
          
          const matches = imageData.match(/^data:(image\/([^;]+));base64,(.+)$/);
          if (matches) {
            const [, mediaType, extension, base64Data] = matches;
            const ext = extension === 'jpeg' ? 'jpg' : extension;
            
            const tempDir = os.tmpdir();
            const filename = `profile-pic-${Date.now()}.${ext}`;
            const filepath = path.join(tempDir, filename);
            
            const buffer = Buffer.from(base64Data, 'base64');
            fs.writeFileSync(filepath, buffer);
            
            return {
              content: [{ 
                type: "text", 
                text: `Profile pic generated!\n\n**Vibe:** ${description}\n**Subject:** ${subject}\n**Style:** ${stylePreset?.name || style}\n**Model:** ${model}\n\n**Image saved to:** ${filepath}\n\nUse the message tool to send this image.`
              }],
              details: {
                success: true,
                description: description,
                subject: subject,
                style: stylePreset?.name || style,
                model: model,
                enhanced_prompt: enhancedPrompt,
                image_path: filepath,
                media_type: mediaType
              }
            };
          }
        }
        
        return {
          content: [{ 
            type: "text", 
            text: `Profile pic generated!\n\n**Vibe:** ${description}\n**Subject:** ${subject}\n**Style:** ${stylePreset?.name || style}\n**Model:** ${model}\n\n**Image URL:** ${imageData}`
          }],
          details: {
            success: true,
            description: description,
            subject: subject,
            style: stylePreset?.name || style,
            model: model,
            enhanced_prompt: enhancedPrompt,
            image_url: imageData
          }
        };

      } catch (error: any) {
        return {
          content: [{ type: "text", text: `Profile pic generation failed: ${error.message}` }]
        };
      }
    }
  });
}
