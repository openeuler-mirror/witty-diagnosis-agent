# Installing witty-diagnosis-agent for Codex

Quick setup to enable witty-diagnosis-agent skills in Codex.

## Installation

1. **Clone witty-diagnosis-agent repository**:
   ```bash
   mkdir -p ~/.codex/witty-diagnosis-agent
   cd ~/.codex/witty-diagnosis-agent
   git clone https://gitcode.com/openeuler/witty-diagnosis-agent.git .
   ```

2. **Create personal skills directory**:
   ```bash
   mkdir -p ~/.codex/skills
   ```

3. **Update ~/.codex/AGENTS.md to include this witty-diagnosis-agent section**:
   ```markdown
   ## witty-diagnosis-agent System

   <EXTREMELY_IMPORTANT>
   You have witty-diagnosis-agent skills for intelligent system diagnosis on EulerOS and other Linux systems. RIGHT NOW run: `~/.codex/witty-diagnosis-agent/.codex/witty-diagnosis-agent-codex bootstrap` and follow the instructions it returns.
   </EXTREMELY_IMPORTANT>
   ```

## Verification

Test the installation:
```bash
~/.codex/witty-diagnosis-agent/.codex/witty-diagnosis-agent-codex bootstrap
```

You should see skill listings and bootstrap instructions. The system is now ready for use.