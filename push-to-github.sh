#!/bin/bash

# BorgOS GitHub Push Helper Script

echo "🚀 BorgOS GitHub Repository Setup"
echo "================================="
echo
echo "This script will help you push BorgOS to GitHub."
echo
echo "📋 Prerequisites:"
echo "1. Create a new repository on GitHub:"
echo "   Go to: https://github.com/new"
echo "   Name: borgos"
echo "   Description: AI-First Multi-Agent Operating System"
echo "   Public/Private: Your choice"
echo "   DO NOT initialize with README, .gitignore, or license"
echo
read -p "Have you created the repository on GitHub? (y/n): " created

if [ "$created" != "y" ]; then
    echo "Please create the repository first, then run this script again."
    exit 1
fi

echo
echo "Enter your GitHub username:"
read username

echo "Enter your repository name (default: borgos):"
read reponame
reponame=${reponame:-borgos}

# Set remote
echo
echo "Adding GitHub remote..."
git remote add origin "https://github.com/$username/$reponame.git"

# Verify remote
echo "Remote added:"
git remote -v

echo
echo "📤 Ready to push to GitHub!"
echo "Commands to execute:"
echo "  git push -u origin main"
echo
read -p "Push now? (y/n): " push

if [ "$push" = "y" ]; then
    echo "Pushing to GitHub..."
    git push -u origin main
    
    echo
    echo "✅ Success! Your repository is now on GitHub:"
    echo "   https://github.com/$username/$reponame"
    echo
    echo "📝 Next steps:"
    echo "1. Add topics: ai, multi-agent, docker, fastapi, python"
    echo "2. Add description and website if applicable"
    echo "3. Configure GitHub Pages for documentation"
    echo "4. Set up GitHub Actions secrets:"
    echo "   - DOCKERHUB_USERNAME"
    echo "   - DOCKERHUB_TOKEN"
    echo "   - DISCORD_WEBHOOK (optional)"
    echo "5. Create first release:"
    echo "   git tag -a v2.0.0 -m 'Initial release'"
    echo "   git push origin v2.0.0"
else
    echo
    echo "You can push manually with:"
    echo "  git push -u origin main"
fi