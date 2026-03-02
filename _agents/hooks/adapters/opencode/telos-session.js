// opencode plugin adapter for telos session logging
// Hooks into session.created to inject telos context
import { $ } from "bun";

export const TelosSession = async (ctx) => {
  const { directory } = ctx;

  return {
    "session.created": async (input, output) => {
      try {
        // Call shared session-logger via bash
        const scriptPath = `${process.env.HOME}/.agents/hooks/lib/session-logger.sh`;
        const result = await $`bash -c "source ${scriptPath} && session_log_start"`.text();

        if (result && result.trim()) {
          // Inject context into session
          output.context = output.context || [];
          output.context.push({
            role: "system",
            content: result.trim()
          });
        }
      } catch (error) {
        console.error("[telos] Failed to load session context:", error.message);
      }
    }
  };
};
