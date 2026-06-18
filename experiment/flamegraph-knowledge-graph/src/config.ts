import dotenv from 'dotenv';
import { createOpenAI } from '@ai-sdk/openai';

// 加载 .env 文件配置
dotenv.config();

export const config = {
  // LLM (DeepSeek) 配置
  openaiApiKey: process.env.OPENAI_API_KEY || '',
  openaiBaseUrl: process.env.OPENAI_BASE_URL || 'https://api.deepseek.com/v1',
  llmModel: process.env.LLM_MODEL_NAME || 'deepseek-chat',

  // Embedding 配置
  embeddingApiKey: process.env.EMBEDDING_API_KEY || process.env.OPENAI_API_KEY || '',
  embeddingBaseUrl: process.env.EMBEDDING_BASE_URL || 'https://openrouter.ai/api/v1',
  embeddingModel: process.env.EMBEDDING_MODEL_NAME || 'text-embedding-3-small',
  embeddingDim: parseInt(process.env.EMBEDDING_DIM || '1536', 10),
};

// 如果没有配置 API Key，可以抛出警告或者错误
if (!config.openaiApiKey) {
  console.warn('⚠️ Warning: OPENAI_API_KEY is not set in .env file.');
}
if (!config.embeddingApiKey) {
  console.warn('⚠️ Warning: EMBEDDING_API_KEY is not set in .env file.');
}

// 创建并导出 LLM 专用的客户端实例
export const openaiClient = createOpenAI({
  apiKey: config.openaiApiKey,
  baseURL: config.openaiBaseUrl,
});

// 创建并导出 Embedding 专用的客户端实例
export const embeddingClient = createOpenAI({
  apiKey: config.embeddingApiKey,
  baseURL: config.embeddingBaseUrl,
});

export const llm = openaiClient(config.llmModel);
export const embeddingModel = embeddingClient.embedding(config.embeddingModel);
