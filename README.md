# Polyglot Benchmark

Multi-language code generation evaluation (C++, Go, Java, JavaScript, Python, Rust).

## Quick Start

```bash
./setup.sh                                          # First time only
./run.sh --api-url <url> --api-key <key> --model <model>
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--api-url` | API base URL | required |
| `--api-key` | API key | required |
| `--model` | Model name | required |
| `--edit-format` | whole, diff, udiff | whole |
| `--threads` | Parallel threads | 10 |
| `--language` | Filter by language | all |

## Config File

```bash
./run.sh --config config.json
```

```json
{
  "api_url": "https://api.example.com/v1",
  "api_key": "sk-xxx",
  "model": "gpt-4o"
}
```

## Requirements

- Docker Desktop (macOS) or Docker daemon (Linux)
- Git

## Output

`results/result.json`:
```json
{
  "metrics": {
    "main": {"name": "pass@1", "value": 0.85},
    "secondary": {"success_rate": 85.0, "failure_rate": 15.0}
  }
}
```
