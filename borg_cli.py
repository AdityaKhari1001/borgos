#!/opt/borgos/env/bin/python3
"""Borg CLI – Natural language interface to BorgOS."""
import os
import sys
import subprocess
import json
import socket
import requests
from pathlib import Path

OFFLINE_MODEL = os.getenv("BORG_OFFLINE_MODEL", "mistral:7b-instruct-q4_K_M")
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")

def check_online():
    """Check if we have internet connectivity."""
    try:
        requests.get("https://1.1.1.1", timeout=2)
        return True
    except requests.exceptions.RequestException:
        return False

def query_ollama(prompt):
    """Query local Ollama instance."""
    try:
        import ollama
        response = ollama.chat(
            model=OFFLINE_MODEL,
            messages=[{"role": "user", "content": prompt}]
        )
        return response['message']['content']
    except Exception as e:
        return f"Error querying Ollama: {e}"

def query_openrouter(prompt):
    """Query OpenRouter API."""
    try:
        import openai
        openai.api_key = os.getenv("OPENAI_API_KEY")
        openai.base_url = os.getenv("OPENAI_API_BASE", "https://openrouter.ai/api/v1")
        
        try:
            response = openai.chat.completions.create(
                model="openrouter/auto",
                messages=[{"role": "user", "content": prompt}]
            )
            # Dodano logowanie typu i zawartości odpowiedzi
            print(f"DEBUG: OpenRouter API Response Type: {type(response)}")
            print(f"DEBUG: OpenRouter API Response: {response}")
            return response.choices[0].message.content
        except openai.APIError as e:
            return f"OpenRouter API Error: {e.status_code} - {e.response}"
        except Exception as e:
            return f"Error querying OpenRouter: {e}"
    except Exception as e: 
        return f"Unexpected error in query_openrouter: {e}"

def main():
    # Get prompt from arguments or stdin
    if len(sys.argv) > 1:
        prompt = " ".join(sys.argv[1:])
    else:
        prompt = input("borg> ")
    
    # Determine which backend to use
    online = check_online()
    has_api_key = bool(os.getenv("OPENAI_API_KEY"))
    
    if online and has_api_key:
        print("[Using OpenRouter]")
        result = query_openrouter(prompt)
    else:
        print("[Using Ollama]")
        result = query_ollama(prompt)
    
    print(result)

if __name__ == "__main__":
    main()
