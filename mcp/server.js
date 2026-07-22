#!/usr/bin/env node
// openfox-rag — MCP Server
// Exposes rag_search tool to OpenFox via Model Context Protocol (stdio)

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema
} from '@modelcontextprotocol/sdk/types.js';

// RAG modules
import { chunkByMarkdown } from '../rag/chunker.js';
import { isEmbeddable } from '../rag/filter.js';
import { embedTexts } from '../rag/embedder.js';
import { rerankDocuments } from '../rag/reranker.js';
import { buildBM25Index, searchBM25 } from '../rag/bm25.js';
import { reciprocalRankFusion } from '../rag/rrf.js';
import { loadCache, saveCache } from '../rag/cache.js';

// Configuration from environment
const CONFIG = {
  backendUrl: process.env.RAG_BACKEND_URL || 'http://localhost:8000',
  embeddingModel: process.env.RAG_EMBEDDING_MODEL || 'Qwen3-Embedding-0.6B',
  rerankerModel: process.env.RAG_RERANKER_MODEL || 'Qwen3-Reranker-0.6B',
  defaultVault: process.env.RAG_DEFAULT_VAULT || 'obsidian',
  topK: parseInt(process.env.RAG_TOP_K || '5'),
  rerankCandidates: parseInt(process.env.RAG_RERANK_CANDIDATES || '18'),
  enableReranker: process.env.RAG_ENABLE_RERANKER !== 'false',
  alphaRatio: parseFloat(process.env.RAG_ALPHA_RATIO || '0.36'),
  cacheDir: process.env.RAG_CACHE_DIR || `${process.env.HOME}/.config/openfox/rag-cache`,
  vaults: parseVaults(process.env.RAG_VAULTS || '')
};

function parseVaults(vaultsStr) {
  if (!vaultsStr) return {};
  const vaults = {};
  for (const entry of vaultsStr.split(',')) {
    const [name, path] = entry.split(':');
    if (name && path) vaults[name.trim()] = path.trim();
  }
  return vaults;
}

// MCP Server
const server = new Server(
  { name: 'openfox-rag', version: '0.1.0' },
  { capabilities: { tools: {} } }
);

// List available tools
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'rag_search',
      description:
        'Search local knowledge base (Obsidian vaults, technical docs, procedures). ' +
        'Use when the user asks about their notes, documentation, or when you need ' +
        'to verify a technical reference before coding.',
      inputSchema: {
        type: 'object',
        properties: {
          query: {
            type: 'string',
            description: 'Natural language search query'
          },
          vault: {
            type: 'string',
            default: CONFIG.defaultVault,
            description: `Vault scope: ${Object.keys(CONFIG.vaults).join(', ') || 'obsidian'}, all`
          },
          top_k: {
            type: 'integer',
            default: CONFIG.topK,
            description: 'Number of results to return'
          },
          rerank: {
            type: 'boolean',
            default: CONFIG.enableReranker,
            description: 'Enable cross-encoder reranking (slower but more precise)'
          }
        },
        required: ['query']
      }
    }
  ]
}));

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name !== 'rag_search') {
    return {
      content: [{ type: 'text', text: `Unknown tool: ${name}` }],
      isError: true
    };
  }

  const {
    query,
    vault = CONFIG.defaultVault,
    top_k = CONFIG.topK,
    rerank = CONFIG.enableReranker
  } = args;

  try {
    // TODO: Implement full RAG pipeline
    // 1. Resolve vault paths (single vault, "obsidian" = all obsidian, "all" = everything)
    // 2. Load chunks from cache or index vaults
    // 3. Embed query via POST /v1/embeddings
    // 4. Cosine similarity against all chunk vectors
    // 5. BM25 search against tokenized chunks
    // 6. RRF fusion (k=60)
    // 7. If rerank: send top-N candidates to POST /v1/rerank
    // 8. Format and return results

    return {
      content: [{
        type: 'text',
        text: [
          `RAG search: "${query}"`,
          `Vault: ${vault} | Top K: ${top_k} | Rerank: ${rerank}`,
          `Backend: ${CONFIG.backendUrl}`,
          `Embedding model: ${CONFIG.embeddingModel}`,
          `Reranker model: ${CONFIG.rerankerModel}`,
          '',
          '[Implementation in progress — see https://github.com/cried-nutty-won/rag-system for the reference pipeline]'
        ].join('\n')
      }]
    };
  } catch (error) {
    return {
      content: [{ type: 'text', text: `RAG error: ${error.message}` }],
      isError: true
    };
  }
});

// Start server
const transport = new StdioServerTransport();
await server.connect(transport);
