#!/usr/bin/env node
// BorgOS Node.js Server - AI Integration Hub

const express = require('express');
const axios = require('axios');
const dotenv = require('dotenv');
const { Server } = require('socket.io');
const http = require('http');

// Load environment variables
dotenv.config();

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: {
        origin: "*",
        methods: ["GET", "POST"]
    }
});

// Middleware
app.use(express.json());
app.use(express.static('public'));

// Configuration
const PORT = process.env.NODE_PORT || 3000;
const OLLAMA_HOST = process.env.OLLAMA_HOST || 'http://localhost:11434';
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;
const OPENROUTER_BASE_URL = process.env.OPENROUTER_BASE_URL || 'https://openrouter.ai/api/v1';

// AI Chat endpoint - tries Ollama first, falls back to OpenRouter
app.post('/api/chat', async (req, res) => {
    const { prompt, model } = req.body;
    
    if (!prompt) {
        return res.status(400).json({ error: 'Prompt is required' });
    }
    
    try {
        // Try Ollama first
        const ollamaResponse = await axios.post(
            `${OLLAMA_HOST}/api/generate`,
            {
                model: model || process.env.DEFAULT_OLLAMA_MODEL || 'gemma:2b',
                prompt: prompt,
                stream: false
            },
            { timeout: 30000 }
        );
        
        res.json({
            source: 'ollama',
            response: ollamaResponse.data.response,
            model: ollamaResponse.data.model
        });
    } catch (ollamaError) {
        console.log('Ollama failed, trying OpenRouter...');
        
        // Fall back to OpenRouter if configured
        if (OPENROUTER_API_KEY) {
            try {
                const openRouterResponse = await axios.post(
                    `${OPENROUTER_BASE_URL}/chat/completions`,
                    {
                        model: model || process.env.OPENROUTER_DEFAULT_MODEL || 'google/gemma-2b-it:free',
                        messages: [{ role: 'user', content: prompt }]
                    },
                    {
                        headers: {
                            'Authorization': `Bearer ${OPENROUTER_API_KEY}`,
                            'Content-Type': 'application/json',
                            'HTTP-Referer': 'https://borgtools.ddns.net',
                            'X-Title': 'BorgOS'
                        },
                        timeout: 30000
                    }
                );
                
                res.json({
                    source: 'openrouter',
                    response: openRouterResponse.data.choices[0].message.content,
                    model: openRouterResponse.data.model
                });
            } catch (openRouterError) {
                res.status(500).json({ 
                    error: 'Both AI services failed',
                    details: {
                        ollama: ollamaError.message,
                        openrouter: openRouterError.message
                    }
                });
            }
        } else {
            res.status(500).json({ 
                error: 'Ollama unavailable and OpenRouter not configured',
                details: ollamaError.message
            });
        }
    }
});

// List available models
app.get('/api/models', async (req, res) => {
    const models = {
        ollama: [],
        openrouter: []
    };
    
    // Get Ollama models
    try {
        const response = await axios.get(`${OLLAMA_HOST}/api/tags`);
        models.ollama = response.data.models || [];
    } catch (error) {
        console.error('Failed to get Ollama models:', error.message);
    }
    
    // Add OpenRouter free models if configured
    if (OPENROUTER_API_KEY) {
        models.openrouter = [
            'google/gemma-2b-it:free',
            'meta-llama/llama-3.2-3b-instruct:free',
            'mistralai/mistral-7b-instruct:free',
            'huggingfaceh4/zephyr-7b-beta:free'
        ];
    }
    
    res.json(models);
});

// Health check
app.get('/health', async (req, res) => {
    const status = {
        server: 'healthy',
        ollama: 'unknown',
        openrouter: 'unknown'
    };
    
    // Check Ollama
    try {
        await axios.get(`${OLLAMA_HOST}/api/tags`, { timeout: 5000 });
        status.ollama = 'healthy';
    } catch (error) {
        status.ollama = 'unavailable';
    }
    
    // Check OpenRouter
    if (OPENROUTER_API_KEY) {
        status.openrouter = 'configured';
    } else {
        status.openrouter = 'not configured';
    }
    
    res.json(status);
});

// WebSocket for real-time AI streaming
io.on('connection', (socket) => {
    console.log('Client connected:', socket.id);
    
    socket.on('chat', async (data) => {
        const { prompt, model } = data;
        
        try {
            // Stream from Ollama
            const response = await axios.post(
                `${OLLAMA_HOST}/api/generate`,
                {
                    model: model || 'gemma:2b',
                    prompt: prompt,
                    stream: true
                },
                {
                    responseType: 'stream'
                }
            );
            
            response.data.on('data', (chunk) => {
                socket.emit('response', chunk.toString());
            });
            
            response.data.on('end', () => {
                socket.emit('done');
            });
        } catch (error) {
            socket.emit('error', error.message);
        }
    });
    
    socket.on('disconnect', () => {
        console.log('Client disconnected:', socket.id);
    });
});

// Start server
server.listen(PORT, () => {
    console.log(`BorgOS Node.js Server running on port ${PORT}`);
    console.log(`Health check: http://localhost:${PORT}/health`);
    console.log(`Chat API: http://localhost:${PORT}/api/chat`);
    console.log(`Models API: http://localhost:${PORT}/api/models`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('SIGTERM signal received: closing server');
    server.close(() => {
        console.log('Server closed');
        process.exit(0);
    });
});