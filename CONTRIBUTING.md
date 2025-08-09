# Contributing to BorgOS

Thank you for your interest in contributing to BorgOS! We welcome contributions from the community and are grateful for any help you can provide.

## Table of Contents
- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How to Contribute](#how-to-contribute)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Pull Request Process](#pull-request-process)
- [Reporting Issues](#reporting-issues)
- [Community](#community)

## Code of Conduct

We are committed to providing a welcoming and inclusive environment. Please read our Code of Conduct before contributing:

- Be respectful and inclusive
- Welcome newcomers and help them get started
- Focus on constructive criticism
- Accept feedback gracefully
- Prioritize the community's best interests

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally
3. **Create a branch** for your changes
4. **Make your changes** and test them
5. **Push to your fork** and submit a pull request

## How to Contribute

### Ways to Contribute

- **Code**: Fix bugs, add features, improve performance
- **Documentation**: Improve docs, fix typos, add examples
- **Testing**: Write tests, improve coverage, report bugs
- **Design**: Improve UI/UX, create graphics
- **Community**: Answer questions, review PRs, help newcomers

### Good First Issues

Look for issues labeled `good first issue` or `help wanted` to get started.

### Feature Requests

Open an issue to discuss new features before implementing them.

## Development Setup

### Prerequisites

- Python 3.11+
- Docker and Docker Compose
- Git
- Node.js 18+ (for frontend development)

### Local Development

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/borgos.git
   cd borgos
   ```

2. **Create virtual environment**
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**
   ```bash
   pip install -r core/requirements.txt
   pip install -r requirements-dev.txt
   ```

4. **Set up environment**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

5. **Start services**
   ```bash
   docker-compose up -d postgres redis chromadb
   ```

6. **Run the application**
   ```bash
   python core/main.py
   ```

### Running Tests

```bash
# Unit tests
pytest tests/unit/

# Integration tests
pytest tests/integration/

# All tests with coverage
pytest --cov=core --cov-report=html

# Specific test file
pytest tests/unit/test_api.py -v
```

### Linting and Formatting

```bash
# Format code
black core/
isort core/

# Lint code
flake8 core/
pylint core/

# Type checking
mypy core/
```

## Coding Standards

### Python Style Guide

We follow PEP 8 with some modifications:
- Line length: 120 characters
- Use Black for formatting
- Use isort for import sorting

### Code Structure

```python
"""Module docstring explaining purpose."""

import standard_library
import third_party

from local_module import something


class MyClass:
    """Class docstring with description."""
    
    def __init__(self, param: str) -> None:
        """Initialize with parameter."""
        self.param = param
    
    def method(self) -> str:
        """Method docstring with return description."""
        return self.param


def function(arg1: int, arg2: str) -> bool:
    """
    Function docstring.
    
    Args:
        arg1: Description of arg1
        arg2: Description of arg2
    
    Returns:
        Description of return value
    
    Raises:
        ValueError: When input is invalid
    """
    if arg1 < 0:
        raise ValueError("arg1 must be positive")
    return True
```

### Commit Messages

Follow conventional commits:
```
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting
- `refactor`: Code restructuring
- `test`: Tests
- `chore`: Maintenance

Examples:
```
feat(api): add project search endpoint
fix(agent-zero): resolve memory leak in task execution
docs(readme): update installation instructions
```

### Documentation

- Write docstrings for all public functions and classes
- Update README.md for significant changes
- Add inline comments for complex logic
- Include examples in documentation

## Pull Request Process

### Before Submitting

1. **Update your fork**
   ```bash
   git remote add upstream https://github.com/original/borgos.git
   git fetch upstream
   git rebase upstream/main
   ```

2. **Run tests**
   ```bash
   pytest tests/
   ```

3. **Check code quality**
   ```bash
   black --check core/
   flake8 core/
   mypy core/
   ```

4. **Update documentation**
   - Update README if needed
   - Add/update docstrings
   - Update CHANGELOG.md

### PR Guidelines

1. **Title**: Clear and descriptive
2. **Description**: Explain what and why
3. **Link issues**: Reference related issues
4. **Screenshots**: Include for UI changes
5. **Tests**: Add tests for new features
6. **Documentation**: Update relevant docs

### PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Tests pass locally
- [ ] Added new tests
- [ ] Updated existing tests

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No new warnings
- [ ] Breaking changes documented
```

### Review Process

1. Automated checks must pass
2. At least one maintainer review required
3. Address review feedback
4. Maintainer merges when approved

## Reporting Issues

### Bug Reports

Include:
- Clear title and description
- Steps to reproduce
- Expected vs actual behavior
- System information
- Error messages and logs
- Screenshots if applicable

### Feature Requests

Include:
- Use case and motivation
- Proposed solution
- Alternative solutions considered
- Additional context

### Security Issues

**DO NOT** open public issues for security vulnerabilities.
Email security@borgos.ai with:
- Description of vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

## Testing Guidelines

### Test Structure

```python
import pytest
from unittest.mock import Mock, patch

class TestFeature:
    """Test suite for Feature."""
    
    def setup_method(self):
        """Set up test fixtures."""
        self.fixture = Mock()
    
    def test_normal_case(self):
        """Test normal operation."""
        result = function(valid_input)
        assert result == expected_output
    
    def test_edge_case(self):
        """Test edge cases."""
        with pytest.raises(ValueError):
            function(invalid_input)
    
    @patch('module.external_service')
    def test_with_mock(self, mock_service):
        """Test with mocked dependencies."""
        mock_service.return_value = "mocked"
        result = function()
        assert result == "expected"
```

### Coverage Requirements

- New features: >80% coverage
- Bug fixes: Include regression tests
- Refactoring: Maintain existing coverage

## Documentation

### API Documentation

- Use OpenAPI/Swagger specifications
- Include request/response examples
- Document error codes
- Provide SDK examples

### Code Documentation

```python
def complex_function(
    param1: str,
    param2: Optional[int] = None,
    **kwargs: Any
) -> Dict[str, Any]:
    """
    Perform complex operation.
    
    This function does something complex that needs explanation.
    It handles various edge cases and has specific behavior.
    
    Args:
        param1: The primary parameter
        param2: Optional secondary parameter (default: None)
        **kwargs: Additional keyword arguments:
            - option1 (bool): Enable feature X
            - option2 (str): Configuration value
    
    Returns:
        Dictionary containing:
            - result: The operation result
            - metadata: Additional information
    
    Raises:
        ValueError: If param1 is empty
        TypeError: If param2 is not numeric
    
    Example:
        >>> result = complex_function("test", param2=42)
        >>> print(result['result'])
        'success'
    
    Note:
        This function has side effects on the global state.
    """
    pass
```

## Release Process

1. Update version in `__version__`
2. Update CHANGELOG.md
3. Create release PR
4. After merge, tag release
5. GitHub Actions builds and publishes

## Community

### Communication Channels

- **GitHub Discussions**: General discussion
- **Discord**: Real-time chat
- **GitHub Issues**: Bug reports and features
- **Twitter**: @BorgOSAI for updates

### Getting Help

- Check documentation first
- Search existing issues
- Ask in Discord #help channel
- Open a discussion for complex questions

### Recognition

Contributors are recognized in:
- CONTRIBUTORS.md file
- Release notes
- Project website
- Annual contributor report

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Questions?

Feel free to:
- Open a discussion on GitHub
- Ask in Discord
- Email maintainers@borgos.ai

Thank you for contributing to BorgOS! 🚀