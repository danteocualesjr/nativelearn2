//
//  AcademyContent.swift
//  leanring-buddy
//
//  Static curriculum data for the Academy tab. Each AI tool has a set of
//  guided lessons that can launch focused Sparkle tutoring sessions.
//  Progress is derived from ConversationStore — no separate persistence.
//

import Foundation

// MARK: - Category

enum AcademyCategory: String, CaseIterable, Identifiable {
    case codeEditors = "Code Editors"
    case aiAssistants = "AI Assistants"
    case designAndPrototyping = "Design & Prototyping"
    case research = "Research"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .codeEditors: return "curlybraces"
        case .aiAssistants: return "cpu"
        case .designAndPrototyping: return "paintbrush"
        case .research: return "magnifyingglass"
        }
    }
}

// MARK: - Difficulty

enum AcademyDifficulty: String, Codable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"

    var colorHex: String {
        switch self {
        case .beginner: return "#059669"
        case .intermediate: return "#d97706"
        case .advanced: return "#dc2626"
        }
    }
}

// MARK: - Lesson

struct AcademyLesson: Identifiable {
    let id: String
    let title: String
    let description: String
    let estimatedMinutes: Int
    let learningObjectives: [String]
    /// Appended to the system prompt when this lesson is active so Sparkle
    /// knows the user is in a guided lesson and what to focus on.
    let systemPromptContext: String
}

// MARK: - Tool

struct AcademyTool: Identifiable {
    let id: String
    let name: String
    let iconName: String
    let description: String
    let difficulty: AcademyDifficulty
    let category: AcademyCategory
    let lessons: [AcademyLesson]
    /// Keywords used to detect whether conversations relate to this tool
    /// (same pattern as recognizedAITools on the Dashboard).
    let matchKeywords: [String]
}

// MARK: - Catalog

struct AcademyCatalog {
    static let tools: [AcademyTool] = [

        // ── Code Editors ───────────────────────────────────────

        AcademyTool(
            id: "cursor",
            name: "Cursor",
            iconName: "chevron.left.forwardslash.chevron.right",
            description: "AI-first code editor built on VS Code. Write, edit, and debug code with AI assistance.",
            difficulty: .beginner,
            category: .codeEditors,
            lessons: [
                AcademyLesson(
                    id: "cursor-1",
                    title: "Your First AI Edit",
                    description: "Open a file and use Cmd+K to edit code with AI inline.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Open a project in Cursor",
                        "Use Cmd+K to invoke inline AI edits",
                        "Accept or reject AI suggestions",
                    ],
                    systemPromptContext: "the user is in a guided lesson about making their first AI edit in Cursor. walk them through opening a file and using cmd+k to edit code with AI. focus on one step at a time. point at the relevant UI elements as you teach."
                ),
                AcademyLesson(
                    id: "cursor-2",
                    title: "Tab Completion",
                    description: "Write a function and watch Cursor autocomplete the rest.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Start typing a function signature",
                        "See ghost text suggestions appear",
                        "Press Tab to accept completions",
                    ],
                    systemPromptContext: "the user is learning about Cursor's tab completion. help them write a function and see autocomplete suggestions. explain the ghost text and how pressing tab accepts it. keep it practical — have them try it."
                ),
                AcademyLesson(
                    id: "cursor-3",
                    title: "Chat & Composer",
                    description: "Use the sidebar chat for questions and Composer for multi-file edits.",
                    estimatedMinutes: 8,
                    learningObjectives: [
                        "Open the AI chat sidebar with Cmd+L",
                        "Ask questions about their codebase",
                        "Use Composer for multi-file changes",
                    ],
                    systemPromptContext: "the user is learning about Cursor's chat and composer. teach them cmd+l for the chat sidebar and how to ask questions about their code. then introduce composer for making changes across multiple files."
                ),
                AcademyLesson(
                    id: "cursor-4",
                    title: "Using @ Context",
                    description: "Reference files, docs, and your codebase in AI prompts.",
                    estimatedMinutes: 6,
                    learningObjectives: [
                        "Use @file to reference specific files",
                        "Use @codebase for broad context",
                        "Use @docs to reference documentation",
                    ],
                    systemPromptContext: "the user is learning about @ context references in Cursor. show them how typing @ in the chat gives them options like @file, @codebase, and @docs. have them try referencing a specific file in their project."
                ),
                AcademyLesson(
                    id: "cursor-5",
                    title: "Agent Mode",
                    description: "Let Cursor autonomously implement features across your project.",
                    estimatedMinutes: 10,
                    learningObjectives: [
                        "Enable Agent mode in Composer",
                        "Give a high-level feature description",
                        "Review and approve AI-generated changes",
                    ],
                    systemPromptContext: "the user is learning about agent mode in Cursor. explain how it lets the AI autonomously make changes across multiple files. guide them through enabling it and giving it a task. emphasize reviewing the changes before accepting."
                ),
            ],
            matchKeywords: ["cursor"]
        ),

        AcademyTool(
            id: "windsurf",
            name: "Windsurf",
            iconName: "wind",
            description: "AI-powered code editor with Cascade, an agentic coding assistant.",
            difficulty: .beginner,
            category: .codeEditors,
            lessons: [
                AcademyLesson(
                    id: "windsurf-1",
                    title: "Getting Started with Windsurf",
                    description: "Set up your first project and explore the interface.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Install and open Windsurf",
                        "Explore the editor layout",
                        "Open a project folder",
                    ],
                    systemPromptContext: "the user is getting started with Windsurf editor. help them explore the interface and understand the layout. point at key areas like the file explorer, editor, and terminal."
                ),
                AcademyLesson(
                    id: "windsurf-2",
                    title: "Cascade Chat",
                    description: "Use Cascade to ask questions and get code suggestions.",
                    estimatedMinutes: 6,
                    learningObjectives: [
                        "Open the Cascade panel",
                        "Ask Cascade about your code",
                        "Apply suggested changes",
                    ],
                    systemPromptContext: "the user is learning about Cascade in Windsurf. show them how to open the Cascade panel and ask questions about their code. walk them through applying a suggestion."
                ),
                AcademyLesson(
                    id: "windsurf-3",
                    title: "Agentic Coding with Cascade",
                    description: "Let Cascade make multi-file changes autonomously.",
                    estimatedMinutes: 8,
                    learningObjectives: [
                        "Give Cascade a multi-step task",
                        "Watch it plan and execute changes",
                        "Review the diff before accepting",
                    ],
                    systemPromptContext: "the user is learning about agentic coding with Cascade in Windsurf. guide them through giving Cascade a larger task and watching it plan and execute changes across files. emphasize the review step."
                ),
            ],
            matchKeywords: ["windsurf"]
        ),

        AcademyTool(
            id: "github-copilot",
            name: "GitHub Copilot",
            iconName: "airplane",
            description: "AI pair programmer that suggests code as you type, integrated into VS Code and other editors.",
            difficulty: .beginner,
            category: .codeEditors,
            lessons: [
                AcademyLesson(
                    id: "copilot-1",
                    title: "Setting Up Copilot",
                    description: "Install GitHub Copilot and see your first suggestion.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Install the Copilot extension",
                        "Sign in with GitHub",
                        "See your first inline suggestion",
                    ],
                    systemPromptContext: "the user is setting up GitHub Copilot for the first time. help them install the extension, sign in, and see their first code suggestion. make sure they understand how to accept or dismiss suggestions."
                ),
                AcademyLesson(
                    id: "copilot-2",
                    title: "Writing with Copilot",
                    description: "Write functions and let Copilot fill in the implementation.",
                    estimatedMinutes: 6,
                    learningObjectives: [
                        "Write a function comment describing what you want",
                        "Let Copilot generate the implementation",
                        "Cycle through alternative suggestions",
                    ],
                    systemPromptContext: "the user is learning to write code with GitHub Copilot. teach them to write descriptive comments and let Copilot generate implementations. show them how to cycle through alternatives with keyboard shortcuts."
                ),
                AcademyLesson(
                    id: "copilot-3",
                    title: "Copilot Chat",
                    description: "Use Copilot Chat to ask questions and get explanations.",
                    estimatedMinutes: 6,
                    learningObjectives: [
                        "Open Copilot Chat panel",
                        "Ask about code in your project",
                        "Use slash commands like /explain and /fix",
                    ],
                    systemPromptContext: "the user is learning about Copilot Chat. show them how to open the chat panel and use slash commands like /explain and /fix. have them try asking about a piece of code in their project."
                ),
            ],
            matchKeywords: ["copilot", "github copilot"]
        ),

        // ── AI Assistants ──────────────────────────────────────

        AcademyTool(
            id: "claude",
            name: "Claude",
            iconName: "bubble.left.and.text.bubble.right",
            description: "Anthropic's conversational AI assistant for writing, analysis, coding, and creative work.",
            difficulty: .beginner,
            category: .aiAssistants,
            lessons: [
                AcademyLesson(
                    id: "claude-1",
                    title: "Your First Conversation",
                    description: "Start chatting with Claude and learn how to get great answers.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Navigate to claude.ai",
                        "Start a new conversation",
                        "Write a clear, specific prompt",
                    ],
                    systemPromptContext: "the user is learning to use Claude for the first time. help them navigate to claude.ai, start a conversation, and understand how to write clear prompts. teach them that specificity gets better results."
                ),
                AcademyLesson(
                    id: "claude-2",
                    title: "Projects & Context",
                    description: "Use Claude Projects to give Claude persistent context about your work.",
                    estimatedMinutes: 7,
                    learningObjectives: [
                        "Create a Claude Project",
                        "Add files and instructions",
                        "Chat within the project context",
                    ],
                    systemPromptContext: "the user is learning about Claude Projects. show them how to create a project, add files or documents for persistent context, and how conversations inside a project have that context automatically."
                ),
                AcademyLesson(
                    id: "claude-3",
                    title: "Artifacts & Code",
                    description: "Get Claude to create code, documents, and interactive artifacts.",
                    estimatedMinutes: 6,
                    learningObjectives: [
                        "Ask Claude to write code",
                        "Use artifacts for rich outputs",
                        "Iterate on generated content",
                    ],
                    systemPromptContext: "the user is learning about Claude's artifacts. teach them how asking for code, documents, or visualizations creates artifacts they can interact with. show them how to iterate and refine outputs."
                ),
            ],
            matchKeywords: ["claude"]
        ),

        AcademyTool(
            id: "claude-code",
            name: "Claude Code",
            iconName: "terminal",
            description: "Agentic coding tool that lives in your terminal and can read, write, and run code.",
            difficulty: .intermediate,
            category: .aiAssistants,
            lessons: [
                AcademyLesson(
                    id: "claude-code-1",
                    title: "Installing Claude Code",
                    description: "Set up Claude Code in your terminal and run your first command.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Install Claude Code via npm",
                        "Authenticate with your API key",
                        "Run your first claude command",
                    ],
                    systemPromptContext: "the user is installing Claude Code. walk them through the npm install, authentication, and running their first command. make sure they have node and npm set up first."
                ),
                AcademyLesson(
                    id: "claude-code-2",
                    title: "Exploring a Codebase",
                    description: "Use Claude Code to understand an unfamiliar project.",
                    estimatedMinutes: 7,
                    learningObjectives: [
                        "Navigate to a project directory",
                        "Ask Claude Code to explain the codebase",
                        "Ask specific questions about functions or files",
                    ],
                    systemPromptContext: "the user is learning to explore codebases with Claude Code. have them cd into a project and ask claude code to explain the structure. then drill into specific files or functions."
                ),
                AcademyLesson(
                    id: "claude-code-3",
                    title: "Making Changes",
                    description: "Ask Claude Code to implement features and fix bugs in your project.",
                    estimatedMinutes: 8,
                    learningObjectives: [
                        "Describe a change you want",
                        "Review the proposed diff",
                        "Accept or reject changes",
                    ],
                    systemPromptContext: "the user is learning to make code changes with Claude Code. guide them through describing a change, reviewing the proposed diff, and accepting or rejecting it. emphasize reviewing before accepting."
                ),
                AcademyLesson(
                    id: "claude-code-4",
                    title: "Advanced Workflows",
                    description: "Use Claude Code for test-driven development, git workflows, and multi-step tasks.",
                    estimatedMinutes: 10,
                    learningObjectives: [
                        "Chain multiple commands together",
                        "Use Claude Code for git operations",
                        "Run tests and fix failures iteratively",
                    ],
                    systemPromptContext: "the user is learning advanced Claude Code workflows. teach them how to chain tasks like writing tests then implementing the code, or making changes and committing them. this is about building real workflows."
                ),
            ],
            matchKeywords: ["claude code"]
        ),

        AcademyTool(
            id: "chatgpt",
            name: "ChatGPT",
            iconName: "ellipsis.bubble",
            description: "OpenAI's conversational AI for writing, coding, brainstorming, and analysis.",
            difficulty: .beginner,
            category: .aiAssistants,
            lessons: [
                AcademyLesson(
                    id: "chatgpt-1",
                    title: "Getting Started with ChatGPT",
                    description: "Create an account and learn how to get useful responses.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Create an OpenAI account",
                        "Start a new chat",
                        "Learn prompt basics for good answers",
                    ],
                    systemPromptContext: "the user is getting started with ChatGPT. help them sign up, start a chat, and understand how to write prompts that get useful results. teach them about being specific and giving context."
                ),
                AcademyLesson(
                    id: "chatgpt-2",
                    title: "Custom GPTs & Memory",
                    description: "Create custom GPTs and use ChatGPT's memory features.",
                    estimatedMinutes: 7,
                    learningObjectives: [
                        "Explore the GPT store",
                        "Create a custom GPT",
                        "Understand how memory works",
                    ],
                    systemPromptContext: "the user is learning about custom GPTs and memory in ChatGPT. show them the GPT store, walk them through creating a simple custom GPT, and explain how memory lets ChatGPT remember things across conversations."
                ),
                AcademyLesson(
                    id: "chatgpt-3",
                    title: "Advanced Prompting",
                    description: "Use system prompts, chain-of-thought, and multi-turn techniques.",
                    estimatedMinutes: 8,
                    learningObjectives: [
                        "Use system instructions effectively",
                        "Break complex tasks into steps",
                        "Refine outputs through conversation",
                    ],
                    systemPromptContext: "the user is learning advanced prompting with ChatGPT. teach them about using system instructions, breaking complex tasks into steps, and refining outputs through multi-turn conversation. give practical examples they can try."
                ),
            ],
            matchKeywords: ["chatgpt", "chat gpt"]
        ),

        AcademyTool(
            id: "codex",
            name: "Codex",
            iconName: "server.rack",
            description: "OpenAI's cloud-based coding agent that runs tasks in a sandboxed environment.",
            difficulty: .advanced,
            category: .aiAssistants,
            lessons: [
                AcademyLesson(
                    id: "codex-1",
                    title: "Introduction to Codex",
                    description: "Understand what Codex is and when to use it vs other tools.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Understand Codex's sandboxed environment",
                        "Know when Codex is the right tool",
                        "Access Codex through ChatGPT",
                    ],
                    systemPromptContext: "the user is learning about OpenAI Codex. explain what makes it different from other coding tools — it runs in a sandboxed cloud environment and can execute code. help them understand when to use it vs cursor or claude code."
                ),
                AcademyLesson(
                    id: "codex-2",
                    title: "Your First Codex Task",
                    description: "Give Codex a coding task and review the results.",
                    estimatedMinutes: 8,
                    learningObjectives: [
                        "Write a clear task description",
                        "Submit a task to Codex",
                        "Review generated code and tests",
                    ],
                    systemPromptContext: "the user is running their first Codex task. guide them through writing a clear task description, submitting it, and reviewing the generated code. explain how Codex creates and runs tests to verify its work."
                ),
                AcademyLesson(
                    id: "codex-3",
                    title: "Codex for Real Projects",
                    description: "Connect Codex to your repository and use it for real development work.",
                    estimatedMinutes: 10,
                    learningObjectives: [
                        "Connect a GitHub repository",
                        "Use Codex for feature implementation",
                        "Review and merge Codex PRs",
                    ],
                    systemPromptContext: "the user is learning to use Codex on real projects. help them connect a repository and give Codex a meaningful task. teach them about reviewing the PR it creates and the importance of good task descriptions."
                ),
            ],
            matchKeywords: ["codex"]
        ),

        AcademyTool(
            id: "gemini",
            name: "Gemini",
            iconName: "sparkles",
            description: "Google's multimodal AI assistant with deep Google Workspace integration.",
            difficulty: .beginner,
            category: .aiAssistants,
            lessons: [
                AcademyLesson(
                    id: "gemini-1",
                    title: "Getting Started with Gemini",
                    description: "Explore Gemini's interface and multimodal capabilities.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Navigate to gemini.google.com",
                        "Start a conversation",
                        "Upload an image and ask about it",
                    ],
                    systemPromptContext: "the user is getting started with Google Gemini. help them navigate to it, start chatting, and try its multimodal features like uploading an image. highlight what makes Gemini different."
                ),
                AcademyLesson(
                    id: "gemini-2",
                    title: "Gemini in Google Workspace",
                    description: "Use Gemini inside Gmail, Docs, and Sheets.",
                    estimatedMinutes: 7,
                    learningObjectives: [
                        "Use Gemini to draft emails in Gmail",
                        "Generate content in Google Docs",
                        "Analyze data in Google Sheets",
                    ],
                    systemPromptContext: "the user is learning about Gemini inside Google Workspace. show them how to use Gemini in Gmail for drafting, in Docs for content generation, and in Sheets for data analysis. focus on the one they have open."
                ),
                AcademyLesson(
                    id: "gemini-3",
                    title: "Gemini for Code",
                    description: "Use Gemini for coding tasks and technical problem-solving.",
                    estimatedMinutes: 6,
                    learningObjectives: [
                        "Ask Gemini coding questions",
                        "Use code execution in Gemini",
                        "Compare Gemini's strengths with other assistants",
                    ],
                    systemPromptContext: "the user is learning to use Gemini for coding. help them ask technical questions, try the code execution feature, and understand when Gemini is a good choice vs other coding tools."
                ),
            ],
            matchKeywords: ["gemini"]
        ),

        // ── Design & Prototyping ───────────────────────────────

        AcademyTool(
            id: "replit",
            name: "Replit",
            iconName: "play.rectangle",
            description: "Browser-based IDE with AI that can build, deploy, and host full applications.",
            difficulty: .beginner,
            category: .designAndPrototyping,
            lessons: [
                AcademyLesson(
                    id: "replit-1",
                    title: "Your First Repl",
                    description: "Create a new project and run code in the browser.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Create a Replit account",
                        "Start a new Repl",
                        "Write and run your first code",
                    ],
                    systemPromptContext: "the user is creating their first Repl. walk them through signing up, creating a new repl, and running some code. make it feel exciting — they're about to build something that runs instantly in the browser."
                ),
                AcademyLesson(
                    id: "replit-2",
                    title: "Replit AI Agent",
                    description: "Use Replit's AI to build an app from a description.",
                    estimatedMinutes: 8,
                    learningObjectives: [
                        "Describe what you want to build",
                        "Watch the AI agent create your app",
                        "Make follow-up edits with AI",
                    ],
                    systemPromptContext: "the user is learning about Replit's AI agent. help them describe an app they want to build and watch the agent create it. then teach them to make follow-up edits by chatting with the AI."
                ),
                AcademyLesson(
                    id: "replit-3",
                    title: "Deploying Your App",
                    description: "Deploy your Replit project to a live URL anyone can visit.",
                    estimatedMinutes: 6,
                    learningObjectives: [
                        "Use Replit's deploy feature",
                        "Get a live URL for your project",
                        "Understand hosting basics",
                    ],
                    systemPromptContext: "the user is learning to deploy with Replit. walk them through the deploy button, getting a live URL, and understanding that their app is now running on Replit's servers. celebrate the win — they just shipped something."
                ),
            ],
            matchKeywords: ["replit"]
        ),

        AcademyTool(
            id: "v0",
            name: "v0",
            iconName: "rectangle.and.pencil.and.ellipsis",
            description: "Vercel's AI tool for generating production-ready UI components from descriptions.",
            difficulty: .intermediate,
            category: .designAndPrototyping,
            lessons: [
                AcademyLesson(
                    id: "v0-1",
                    title: "Generating Your First Component",
                    description: "Describe a UI component and get production-ready code.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Navigate to v0.dev",
                        "Describe a UI component in natural language",
                        "Preview and iterate on the generated output",
                    ],
                    systemPromptContext: "the user is trying v0 for the first time. help them navigate to v0.dev and describe a UI component they want. teach them how to preview the result and iterate with follow-up prompts."
                ),
                AcademyLesson(
                    id: "v0-2",
                    title: "Using v0 with Your Project",
                    description: "Copy v0 components into your codebase and customize them.",
                    estimatedMinutes: 7,
                    learningObjectives: [
                        "Copy generated code from v0",
                        "Integrate into a React/Next.js project",
                        "Customize styles and behavior",
                    ],
                    systemPromptContext: "the user is learning to use v0 output in their own project. help them copy the generated code, understand the dependencies (like shadcn/ui), and integrate it into their codebase."
                ),
                AcademyLesson(
                    id: "v0-3",
                    title: "Advanced v0 Prompting",
                    description: "Write detailed prompts for complex layouts and interactions.",
                    estimatedMinutes: 8,
                    learningObjectives: [
                        "Describe complex multi-section layouts",
                        "Specify interactions and animations",
                        "Upload screenshots as reference",
                    ],
                    systemPromptContext: "the user is learning advanced v0 prompting. teach them to write detailed descriptions for complex layouts, specify interactions, and use screenshot references. show them the difference between vague and specific prompts."
                ),
            ],
            matchKeywords: ["v0", "v zero", "vercel v0"]
        ),

        AcademyTool(
            id: "bolt",
            name: "Bolt",
            iconName: "bolt.fill",
            description: "AI-powered full-stack development tool that builds and deploys web apps in the browser.",
            difficulty: .beginner,
            category: .designAndPrototyping,
            lessons: [
                AcademyLesson(
                    id: "bolt-1",
                    title: "Building with Bolt",
                    description: "Describe an app and watch Bolt build it live.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Navigate to bolt.new",
                        "Describe your app idea",
                        "Watch Bolt generate and preview it",
                    ],
                    systemPromptContext: "the user is trying Bolt for the first time. help them navigate to bolt.new and describe an app they want to build. walk them through the live preview and how to iterate on it."
                ),
                AcademyLesson(
                    id: "bolt-2",
                    title: "Iterating on Your App",
                    description: "Use follow-up prompts to refine design, features, and functionality.",
                    estimatedMinutes: 7,
                    learningObjectives: [
                        "Make follow-up requests to change the app",
                        "Fix bugs by describing the issue",
                        "Add new pages or features",
                    ],
                    systemPromptContext: "the user is learning to iterate with Bolt. teach them to make follow-up changes, fix issues by describing them conversationally, and add features. the key insight is that building is a conversation."
                ),
                AcademyLesson(
                    id: "bolt-3",
                    title: "Deploying from Bolt",
                    description: "Deploy your Bolt app to a live URL.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Use Bolt's deploy feature",
                        "Share your live app URL",
                        "Understand the hosting setup",
                    ],
                    systemPromptContext: "the user is deploying their Bolt app. walk them through the deploy process and celebrate when they get a live URL. they just went from idea to deployed app using AI."
                ),
            ],
            matchKeywords: ["bolt.new", "bolt"]
        ),

        AcademyTool(
            id: "lovable",
            name: "Lovable",
            iconName: "heart.fill",
            description: "AI-powered app builder focused on creating beautiful, functional web apps from prompts.",
            difficulty: .beginner,
            category: .designAndPrototyping,
            lessons: [
                AcademyLesson(
                    id: "lovable-1",
                    title: "Creating Your First App",
                    description: "Describe an app and let Lovable build it with beautiful defaults.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Sign up for Lovable",
                        "Describe your app idea",
                        "Preview the generated app",
                    ],
                    systemPromptContext: "the user is trying Lovable for the first time. help them sign up and describe an app idea. lovable focuses on beautiful defaults — point out how the generated design looks polished right away."
                ),
                AcademyLesson(
                    id: "lovable-2",
                    title: "Customizing Your App",
                    description: "Use natural language to tweak designs, add features, and connect data.",
                    estimatedMinutes: 7,
                    learningObjectives: [
                        "Change colors, layouts, and styling",
                        "Add new pages and navigation",
                        "Connect to external APIs or databases",
                    ],
                    systemPromptContext: "the user is customizing their Lovable app. teach them to make design changes, add pages, and connect data sources. emphasize describing what they want conversationally."
                ),
                AcademyLesson(
                    id: "lovable-3",
                    title: "Shipping with Lovable",
                    description: "Deploy and share your Lovable-built app with the world.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Deploy to a custom domain",
                        "Share with others",
                        "Iterate based on feedback",
                    ],
                    systemPromptContext: "the user is shipping their Lovable app. walk them through deployment and getting it in front of people. celebrate the accomplishment — they built and shipped a real app with AI."
                ),
            ],
            matchKeywords: ["lovable"]
        ),

        AcademyTool(
            id: "midjourney",
            name: "Midjourney",
            iconName: "photo.artframe",
            description: "AI image generation tool that creates stunning artwork from text descriptions.",
            difficulty: .intermediate,
            category: .designAndPrototyping,
            lessons: [
                AcademyLesson(
                    id: "midjourney-1",
                    title: "Your First Image",
                    description: "Write a prompt and generate your first AI image.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Access Midjourney",
                        "Write an image generation prompt",
                        "Understand the generation process",
                    ],
                    systemPromptContext: "the user is generating their first Midjourney image. help them write a good prompt and understand the generation process. teach them that descriptive, visual language gets the best results."
                ),
                AcademyLesson(
                    id: "midjourney-2",
                    title: "Prompt Engineering for Images",
                    description: "Master the art of writing prompts that produce exactly what you want.",
                    estimatedMinutes: 8,
                    learningObjectives: [
                        "Use style keywords effectively",
                        "Control aspect ratio and quality",
                        "Use reference images",
                    ],
                    systemPromptContext: "the user is learning prompt engineering for Midjourney. teach them about style keywords, parameters like --ar and --q, and using image references. show the difference between vague and specific prompts."
                ),
                AcademyLesson(
                    id: "midjourney-3",
                    title: "Advanced Techniques",
                    description: "Use upscaling, variations, and multi-prompts for professional results.",
                    estimatedMinutes: 8,
                    learningObjectives: [
                        "Upscale and create variations",
                        "Use multi-prompts and negative prompts",
                        "Build a consistent visual style",
                    ],
                    systemPromptContext: "the user is learning advanced Midjourney techniques. teach them about upscaling, variations, multi-prompts with :: syntax, and negative prompting with --no. help them develop a consistent style."
                ),
            ],
            matchKeywords: ["midjourney"]
        ),

        // ── Research ───────────────────────────────────────────

        AcademyTool(
            id: "perplexity",
            name: "Perplexity",
            iconName: "globe.americas",
            description: "AI-powered search engine that provides sourced, conversational answers to complex questions.",
            difficulty: .beginner,
            category: .research,
            lessons: [
                AcademyLesson(
                    id: "perplexity-1",
                    title: "Search with Perplexity",
                    description: "Ask a question and get a sourced, comprehensive answer.",
                    estimatedMinutes: 5,
                    learningObjectives: [
                        "Navigate to perplexity.ai",
                        "Ask a research question",
                        "Read and verify sources",
                    ],
                    systemPromptContext: "the user is trying Perplexity for the first time. help them ask a research question and read the sourced answer. teach them to check the cited sources — that's what makes perplexity powerful."
                ),
                AcademyLesson(
                    id: "perplexity-2",
                    title: "Deep Research with Focus",
                    description: "Use Focus modes and follow-up questions for in-depth research.",
                    estimatedMinutes: 7,
                    learningObjectives: [
                        "Use Focus modes (Academic, Writing, etc.)",
                        "Ask follow-up questions to go deeper",
                        "Use Collections to organize research",
                    ],
                    systemPromptContext: "the user is learning Perplexity's advanced features. teach them about Focus modes for different types of research, how follow-up questions let them drill deeper, and Collections for organizing their findings."
                ),
                AcademyLesson(
                    id: "perplexity-3",
                    title: "Perplexity Pro Search",
                    description: "Use Pro Search for multi-step, thorough research with citations.",
                    estimatedMinutes: 6,
                    learningObjectives: [
                        "Enable Pro Search",
                        "Ask complex multi-part questions",
                        "Export and share findings",
                    ],
                    systemPromptContext: "the user is learning about Perplexity Pro Search. show them how it breaks complex questions into sub-queries for thorough answers. have them try a complex question and compare the results to a regular search."
                ),
            ],
            matchKeywords: ["perplexity"]
        ),
    ]
}
