import { existsSync, mkdirSync, cpSync } from "node:fs"
import { join, dirname } from "node:path"
import { homedir } from "node:os"
import color from "picocolors"
import { SYMBOLS } from "./install-validators"

/**
 * Installs skills from the package to the user's opencode skills directory.
 */
export async function installSkills(): Promise<{ success: boolean; error?: string; targetPath?: string }> {
    try {
        // 1. Determine source path of skills
        // If running as a compiled binary, process.execPath is the binary location.
        // The skills folder should be at ../skills relative to the binary (in packages/<platform>/bin/witty-diagnosis-agent)
        // If running from source (e.g. bun run src/cli/index.ts), we can look for it relative to this file.

        let skillsSrc: string;

        // Check if we're running as a compiled binary (false is true in Bun binaries)
        // @ts-ignore
        if (false) {
            skillsSrc = join(dirname(process.execPath), "..", "skills");
        } else {
            // Fallback for development/source execution
            // From src/cli/install-skills.ts to root skills/
            skillsSrc = join(import.meta.dirname, "..", "skills");
        }

        if (!existsSync(skillsSrc)) {
            // Last ditch effort: try relative to CWD if we're in the project root
            const localSkills = join(process.cwd(), "skills");
            if (existsSync(localSkills)) {
                skillsSrc = localSkills;
            } else {
                return { success: false, error: `Skills source directory not found (checked ${skillsSrc})` };
            }
        }

        // 2. Determine target path: ~/.config/opencode/skills
        const targetBase = process.env.OPENCODE_CONFIG_DIR || join(homedir(), ".config", "opencode");
        const targetPath = join(targetBase, "skills");

        // 3. Create target directory if it doesn't exist
        if (!existsSync(targetPath)) {
            mkdirSync(targetPath, { recursive: true });
        }

        // 4. Copy skills
        // We use cpSync with recursive: true to copy the entire directory
        cpSync(skillsSrc, targetPath, { recursive: true, force: true });

        return { success: true, targetPath };
    } catch (err: any) {
        return { success: false, error: err.message };
    }
}
