#!/usr/bin/env python3
"""
BorgOS Model Manager
Unified interface for managing AI models across multiple providers.
"""
import os
import json
import yaml
import asyncio
import logging
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass
from enum import Enum
import requests
from pathlib import Path
import subprocess
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ModelProvider(Enum):
    """Supported model providers."""
    OLLAMA = "ollama"
    OPENROUTER = "openrouter"
    HUGGINGFACE = "huggingface"

class ModelTier(Enum):
    """Model pricing tiers."""
    FREE = "free"
    PAID = "paid"
    LOCAL = "local"

@dataclass
class Model:
    """Model information."""
    name: str
    provider: ModelProvider
    tier: ModelTier
    context_length: int
    cost_per_token: float = 0.0
    speed_rating: int = 5  # 1-10
    quality_rating: int = 5  # 1-10
    size_gb: float = 0.0
    requires_gpu: bool = False
    languages: List[str] = None
    specialties: List[str] = None

class ModelManager:
    """Manages AI models across multiple providers."""
    
    # OpenRouter FREE models (updated list)
    OPENROUTER_FREE_MODELS = [
        "huggingfaceh4/zephyr-7b-beta:free",
        "openchat/openchat-7b:free",
        "mythomist/mythomax-l2-7b:free",
        "nousresearch/nous-capybara-7b:free",
        "gryphe/mythomist-7b:free",
        "undi95/toppy-m-7b:free",
        "openrouter/cinematika-7b:free",
        "google/gemma-7b-it:free",
        "meta-llama/llama-3-8b-instruct:free",
        "microsoft/phi-3-mini-128k-instruct:free",
        "mistralai/mistral-7b-instruct:free",
        "qwen/qwen-2-7b-instruct:free"
    ]
    
    # HuggingFace FREE tier models
    HUGGINGFACE_FREE_MODELS = [
        "mistralai/Mistral-7B-Instruct-v0.2",
        "mistralai/Mixtral-8x7B-Instruct-v0.1",
        "google/flan-t5-xxl",
        "bigscience/bloom",
        "facebook/opt-66b",
        "EleutherAI/gpt-j-6b",
        "tiiuae/falcon-7b-instruct",
        "codellama/CodeLlama-7b-Instruct-hf",
        "NousResearch/Nous-Hermes-2-Mixtral-8x7B-DPO",
        "deepseek-ai/deepseek-coder-6.7b-instruct",
        "teknium/OpenHermes-2.5-Mistral-7B",
        "microsoft/phi-2"
    ]
    
    # Recommended Ollama models for 8GB RAM
    OLLAMA_RECOMMENDED = {
        "mistral:7b-instruct-q4_K_M": {
            "size_gb": 4.1,
            "quality": 9,
            "speed": 8,
            "specialties": ["coding", "general", "reasoning"]
        },
        "llama3.2:3b-instruct-q4_K_M": {
            "size_gb": 2.0,
            "quality": 7,
            "speed": 10,
            "specialties": ["general", "fast"]
        },
        "deepseek-coder:6.7b-instruct-q4_0": {
            "size_gb": 3.8,
            "quality": 9,
            "speed": 7,
            "specialties": ["coding", "debugging"]
        },
        "qwen2.5-coder:7b-instruct-q4_K_M": {
            "size_gb": 4.0,
            "quality": 9,
            "speed": 7,
            "specialties": ["coding", "multi-language"]
        },
        "codellama:7b-instruct-q4_0": {
            "size_gb": 3.8,
            "quality": 8,
            "speed": 8,
            "specialties": ["coding", "python", "javascript"]
        }
    }
    
    def __init__(self, config_path: str = "/etc/borgos/config.yaml"):
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self.providers = {}
        self._init_providers()
        
    def _load_config(self) -> Dict:
        """Load configuration from YAML file."""
        if self.config_path.exists():
            with open(self.config_path, 'r') as f:
                return yaml.safe_load(f)
        else:
            # Default configuration
            return {
                "providers": {
                    "ollama": {
                        "enabled": True,
                        "default_model": "mistral:7b-instruct-q4_K_M",
                        "host": "http://localhost:11434"
                    },
                    "openrouter": {
                        "enabled": True,
                        "api_key": os.getenv("OPENROUTER_API_KEY", ""),
                        "use_free_only": True,
                        "max_cost_per_day": 0.00
                    },
                    "huggingface": {
                        "enabled": True,
                        "api_key": os.getenv("HF_API_KEY", ""),
                        "use_free_tier": True
                    }
                },
                "routing": {
                    "strategy": "cost_optimized",
                    "fallback_enabled": True,
                    "complexity_routing": True
                }
            }
    
    def _init_providers(self):
        """Initialize provider clients."""
        if self.config["providers"]["ollama"]["enabled"]:
            self.providers["ollama"] = OllamaProvider(
                self.config["providers"]["ollama"]
            )
        
        if self.config["providers"]["openrouter"]["enabled"]:
            self.providers["openrouter"] = OpenRouterProvider(
                self.config["providers"]["openrouter"]
            )
        
        if self.config["providers"]["huggingface"]["enabled"]:
            self.providers["huggingface"] = HuggingFaceProvider(
                self.config["providers"]["huggingface"]
            )
    
    def list_available_models(self, 
                            provider: Optional[str] = None,
                            free_only: bool = False) -> List[Model]:
        """List all available models."""
        models = []
        
        providers_to_check = [provider] if provider else self.providers.keys()
        
        for prov_name in providers_to_check:
            if prov_name in self.providers:
                provider_models = self.providers[prov_name].list_models()
                
                if free_only:
                    provider_models = [m for m in provider_models if m.tier == ModelTier.FREE]
                
                models.extend(provider_models)
        
        return models
    
    async def query_model(self, 
                         prompt: str,
                         model: Optional[str] = None,
                         provider: Optional[str] = None,
                         max_tokens: int = 1000) -> Tuple[str, Dict]:
        """Query a model with automatic routing."""
        # If specific model/provider requested
        if model and provider:
            if provider in self.providers:
                return await self.providers[provider].query(prompt, model, max_tokens)
        
        # Auto-routing based on strategy
        strategy = self.config["routing"]["strategy"]
        
        if strategy == "cost_optimized":
            providers_order = ["ollama", "huggingface", "openrouter"]
        elif strategy == "quality_first":
            providers_order = ["openrouter", "huggingface", "ollama"]
        else:  # balanced
            providers_order = ["ollama", "openrouter", "huggingface"]
        
        # Try providers in order
        for prov_name in providers_order:
            if prov_name not in self.providers:
                continue
            
            try:
                provider = self.providers[prov_name]
                
                # Get appropriate model
                if prov_name == "ollama":
                    model = self.config["providers"]["ollama"]["default_model"]
                elif prov_name == "openrouter" and self.config["providers"]["openrouter"]["use_free_only"]:
                    model = self.OPENROUTER_FREE_MODELS[0]
                elif prov_name == "huggingface" and self.config["providers"]["huggingface"]["use_free_tier"]:
                    model = self.HUGGINGFACE_FREE_MODELS[0]
                else:
                    model = None
                
                response, metadata = await provider.query(prompt, model, max_tokens)
                metadata["provider"] = prov_name
                metadata["model"] = model
                return response, metadata
                
            except Exception as e:
                logger.warning(f"Provider {prov_name} failed: {e}")
                if not self.config["routing"]["fallback_enabled"]:
                    raise
                continue
        
        raise Exception("All providers failed")
    
    def pull_model(self, model_name: str, provider: str = "ollama") -> bool:
        """Download/pull a model."""
        if provider == "ollama" and "ollama" in self.providers:
            return self.providers["ollama"].pull_model(model_name)
        return False
    
    def estimate_cost(self, prompt: str, model: str, provider: str) -> float:
        """Estimate cost for a query."""
        # Rough token estimation
        prompt_tokens = len(prompt.split()) * 1.3
        
        if provider == "openrouter":
            # Check if it's a free model
            if any(model in free_model for free_model in self.OPENROUTER_FREE_MODELS):
                return 0.0
            # Paid models (example rates)
            return prompt_tokens * 0.00001  # $0.01 per 1K tokens
        
        return 0.0  # Local and HF free tier
    
    def get_model_info(self, model_name: str, provider: str) -> Optional[Model]:
        """Get detailed information about a model."""
        if provider in self.providers:
            models = self.providers[provider].list_models()
            for model in models:
                if model.name == model_name:
                    return model
        return None
    
    def save_config(self):
        """Save current configuration to file."""
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.config_path, 'w') as f:
            yaml.dump(self.config, f, default_flow_style=False)

class OllamaProvider:
    """Ollama provider for local models."""
    
    def __init__(self, config: Dict):
        self.config = config
        self.host = config.get("host", "http://localhost:11434")
    
    def list_models(self) -> List[Model]:
        """List available Ollama models."""
        models = []
        try:
            response = requests.get(f"{self.host}/api/tags")
            if response.status_code == 200:
                for model_data in response.json().get("models", []):
                    model = Model(
                        name=model_data["name"],
                        provider=ModelProvider.OLLAMA,
                        tier=ModelTier.LOCAL,
                        context_length=4096,
                        size_gb=model_data.get("size", 0) / (1024**3),
                        speed_rating=8,
                        quality_rating=7
                    )
                    models.append(model)
        except Exception as e:
            logger.error(f"Failed to list Ollama models: {e}")
        return models
    
    async def query(self, prompt: str, model: str, max_tokens: int) -> Tuple[str, Dict]:
        """Query an Ollama model."""
        import ollama
        
        start_time = time.time()
        response = ollama.chat(
            model=model or self.config["default_model"],
            messages=[{"role": "user", "content": prompt}]
        )
        
        return response['message']['content'], {
            "response_time": time.time() - start_time,
            "tokens": len(response['message']['content'].split()),
            "cost": 0.0
        }
    
    def pull_model(self, model_name: str) -> bool:
        """Pull an Ollama model."""
        try:
            result = subprocess.run(
                ["ollama", "pull", model_name],
                capture_output=True,
                text=True
            )
            return result.returncode == 0
        except Exception as e:
            logger.error(f"Failed to pull model {model_name}: {e}")
            return False

class OpenRouterProvider:
    """OpenRouter provider for online models."""
    
    def __init__(self, config: Dict):
        self.config = config
        self.api_key = config.get("api_key", "")
        self.use_free_only = config.get("use_free_only", True)
    
    def list_models(self) -> List[Model]:
        """List available OpenRouter models."""
        models = []
        
        if self.use_free_only:
            # Add free models
            for model_name in ModelManager.OPENROUTER_FREE_MODELS:
                model = Model(
                    name=model_name,
                    provider=ModelProvider.OPENROUTER,
                    tier=ModelTier.FREE,
                    context_length=4096,
                    speed_rating=6,
                    quality_rating=7
                )
                models.append(model)
        else:
            # Add paid models too
            paid_models = [
                ("openai/gpt-4-turbo", 10, 10, 0.01),
                ("anthropic/claude-3-opus", 10, 10, 0.015),
                ("google/gemini-pro", 9, 9, 0.005),
                ("mistralai/mistral-large", 9, 8, 0.004)
            ]
            for name, quality, speed, cost in paid_models:
                model = Model(
                    name=name,
                    provider=ModelProvider.OPENROUTER,
                    tier=ModelTier.PAID,
                    context_length=8192,
                    cost_per_token=cost,
                    speed_rating=speed,
                    quality_rating=quality
                )
                models.append(model)
        
        return models
    
    async def query(self, prompt: str, model: str, max_tokens: int) -> Tuple[str, Dict]:
        """Query an OpenRouter model."""
        import openai
        
        openai.api_key = self.api_key
        openai.base_url = "https://openrouter.ai/api/v1"
        
        start_time = time.time()
        response = openai.chat.completions.create(
            model=model or "huggingfaceh4/zephyr-7b-beta:free",
            messages=[{"role": "user", "content": prompt}],
            max_tokens=max_tokens
        )
        
        content = response.choices[0].message.content
        
        # Calculate cost
        is_free = any(model in free for free in ModelManager.OPENROUTER_FREE_MODELS)
        cost = 0.0 if is_free else (len(content.split()) * 0.00001)
        
        return content, {
            "response_time": time.time() - start_time,
            "tokens": len(content.split()),
            "cost": cost
        }

class HuggingFaceProvider:
    """HuggingFace provider for Inference API."""
    
    def __init__(self, config: Dict):
        self.config = config
        self.api_key = config.get("api_key", "")
        self.use_free_tier = config.get("use_free_tier", True)
        self.api_url = "https://api-inference.huggingface.co/models/"
    
    def list_models(self) -> List[Model]:
        """List available HuggingFace models."""
        models = []
        
        for model_name in ModelManager.HUGGINGFACE_FREE_MODELS:
            model = Model(
                name=model_name,
                provider=ModelProvider.HUGGINGFACE,
                tier=ModelTier.FREE if self.use_free_tier else ModelTier.PAID,
                context_length=2048,
                speed_rating=5,
                quality_rating=7
            )
            models.append(model)
        
        return models
    
    async def query(self, prompt: str, model: str, max_tokens: int) -> Tuple[str, Dict]:
        """Query a HuggingFace model."""
        headers = {}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        
        model = model or "mistralai/Mistral-7B-Instruct-v0.2"
        url = f"{self.api_url}{model}"
        
        payload = {
            "inputs": prompt,
            "parameters": {
                "max_new_tokens": max_tokens,
                "temperature": 0.7,
                "return_full_text": False
            }
        }
        
        start_time = time.time()
        response = requests.post(url, headers=headers, json=payload)
        
        if response.status_code == 200:
            result = response.json()
            if isinstance(result, list) and len(result) > 0:
                content = result[0].get("generated_text", "")
            else:
                content = str(result)
            
            return content, {
                "response_time": time.time() - start_time,
                "tokens": len(content.split()),
                "cost": 0.0 if self.use_free_tier else len(content.split()) * 0.000001
            }
        else:
            raise Exception(f"HuggingFace API error: {response.status_code}")

# CLI interface
def main():
    """CLI for model manager."""
    import argparse
    
    parser = argparse.ArgumentParser(description="BorgOS Model Manager")
    parser.add_argument("--list", action="store_true", help="List available models")
    parser.add_argument("--free", action="store_true", help="Show only free models")
    parser.add_argument("--pull", help="Pull a model (Ollama only)")
    parser.add_argument("--query", help="Query a model")
    parser.add_argument("--model", help="Specific model to use")
    parser.add_argument("--provider", help="Specific provider to use")
    
    args = parser.parse_args()
    
    manager = ModelManager()
    
    if args.list:
        models = manager.list_available_models(free_only=args.free)
        
        # Group by provider
        by_provider = {}
        for model in models:
            if model.provider.value not in by_provider:
                by_provider[model.provider.value] = []
            by_provider[model.provider.value].append(model)
        
        for provider, models in by_provider.items():
            print(f"\n{provider.upper()} Models:")
            print("-" * 50)
            for model in models:
                tier = "FREE" if model.tier == ModelTier.FREE else "PAID" if model.tier == ModelTier.PAID else "LOCAL"
                size = f"{model.size_gb:.1f}GB" if model.size_gb > 0 else "N/A"
                print(f"  {model.name:<40} [{tier}] Size: {size}")
    
    elif args.pull:
        success = manager.pull_model(args.pull)
        print(f"Pull {'successful' if success else 'failed'} for {args.pull}")
    
    elif args.query:
        async def run_query():
            response, metadata = await manager.query_model(
                args.query,
                model=args.model,
                provider=args.provider
            )
            print(f"\nResponse from {metadata.get('provider')} ({metadata.get('model')}):")
            print("-" * 50)
            print(response)
            print("-" * 50)
            print(f"Time: {metadata.get('response_time', 0):.2f}s")
            print(f"Tokens: {metadata.get('tokens', 0)}")
            print(f"Cost: ${metadata.get('cost', 0):.6f}")
        
        asyncio.run(run_query())

if __name__ == "__main__":
    main()