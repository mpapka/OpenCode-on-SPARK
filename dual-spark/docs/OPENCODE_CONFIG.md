# OpenCode Configuration Guide

This guide covers configuring OpenCode to work with local llama.cpp models.

## Installation

```bash
# Install OpenCode
curl -fsSL https://opencode.sh/install.sh | sh

# Verify installation
opencode --version
```

## Configuration File

OpenCode looks for configuration in these locations (in order):
1. `./opencode.json` (project directory)
2. `~/.config/opencode/opencode.json` (user config)

## Basic Configuration

### For llama.cpp (OpenAI-compatible API)

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llama-cpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local llama.cpp",
      "options": {
        "baseURL": "http://localhost:8080/v1"
      },
      "models": {
        "local-model": {
          "name": "My Local Model",
          "tools": true
        }
      }
    }
  },
  "model": "llama-cpp/local-model"
}
```

### For Ollama

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://localhost:11434/v1"
      },
      "models": {
        "qwen3:8b": {
          "tools": true
        }
      }
    }
  },
  "model": "ollama/qwen3:8b"
}
```

## MiniMax-M2.1 Optimized Config

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llama-cpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "MiniMax-M2.1 (llama.cpp)",
      "options": {
        "baseURL": "http://localhost:8080/v1"
      },
      "models": {
        "minimax-m2.1": {
          "name": "MiniMax-M2.1 UD-Q2_K_XL",
          "tools": true,
          "temperature": 1.0,
          "topP": 0.95
        }
      }
    }
  },
  "model": "llama-cpp/minimax-m2.1"
}
```

## Configuration Options

### Provider Options

| Option | Description |
|--------|-------------|
| `npm` | AI SDK package to use (`@ai-sdk/openai-compatible` for local) |
| `name` | Display name in UI |
| `options.baseURL` | API endpoint URL |

### Model Options

| Option | Description | Default |
|--------|-------------|---------|
| `name` | Display name | Model ID |
| `tools` | Enable tool/function calling | false |
| `temperature` | Sampling temperature | 0.7 |
| `topP` | Top-p sampling | 0.9 |
| `maxTokens` | Maximum output tokens | Model default |

## Multiple Providers

You can configure multiple providers and switch between them:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llama-cpp-local": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local MiniMax",
      "options": {
        "baseURL": "http://localhost:8080/v1"
      },
      "models": {
        "minimax": {
          "tools": true
        }
      }
    },
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama",
      "options": {
        "baseURL": "http://localhost:11434/v1"
      },
      "models": {
        "qwen3:8b": {
          "tools": true
        }
      }
    }
  },
  "model": "llama-cpp-local/minimax"
}
```

Switch models via CLI:
```bash
opencode config set model ollama/qwen3:8b
opencode config set model llama-cpp-local/minimax
```

## Context Window

For agentic tasks, OpenCode needs sufficient context. Ensure your server is configured with adequate context:

```bash
# llama.cpp - set context size
llama-server -m model.gguf --ctx-size 8192

# Ollama - set context in modelfile or at runtime
ollama run model /set parameter num_ctx 8192
```

## Tool Calling

For OpenCode's agentic features (file editing, running commands), the model must support tool/function calling.

Models with good tool support:
- MiniMax-M2.1 (excellent)
- Qwen3 series (very good)
- Llama-3.1+ (good)
- Mistral/Mixtral (good)

Enable in config:
```json
"models": {
  "my-model": {
    "tools": true
  }
}
```

## Troubleshooting

### "Model not found"

Ensure the model ID in config matches what the server expects:
```bash
# Check available models
curl http://localhost:8080/v1/models
```

### "Connection refused"

Server not running. Start it:
```bash
./setup-opencode-minimax.sh --launch-only
```

### Tool calls not working

1. Ensure `"tools": true` in model config
2. Increase context window (8K+ recommended)
3. Try a model known to support tools well

### Slow responses

1. Check GPU utilization: `nvidia-smi`
2. Reduce context size if not needed
3. Try a smaller/faster model for quick tasks

## Environment Variables

```bash
# Override config location
export OPENCODE_CONFIG_DIR=~/.config/opencode

# Debug mode
export DEBUG=opencode:*

# Custom API key (if needed for remote providers)
export OPENAI_API_KEY=your-key
```

## Project-Specific Config

Create `opencode.json` in your project root for project-specific settings:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "llama-cpp/minimax-m2.1",
  "systemPrompt": "You are helping with a Python data science project. Use pandas and numpy conventions."
}
```

This overrides user config for that project only.
