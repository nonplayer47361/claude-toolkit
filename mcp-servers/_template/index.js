#!/usr/bin/env node
/**
 * MCP 서버 템플릿
 * 복사 후 SERVER_NAME, TOOLS 배열, 핸들러를 수정한다.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

// ── 서버 정보 ──────────────────────────────────────────────
const SERVER_NAME = "mcp-server-name";
const SERVER_VERSION = "1.0.0";

// ── 툴 정의 ───────────────────────────────────────────────
const TOOLS = [
  {
    name: "example_tool",
    description: "예시 툴 — 입력 문자열을 그대로 반환한다",
    inputSchema: {
      type: "object",
      properties: {
        input: {
          type: "string",
          description: "처리할 입력값",
        },
      },
      required: ["input"],
    },
  },
  // 툴 추가 시 여기에 객체를 추가
];

// ── 서버 초기화 ────────────────────────────────────────────
const server = new Server(
  { name: SERVER_NAME, version: SERVER_VERSION },
  { capabilities: { tools: {} } }
);

// ── 툴 목록 핸들러 ─────────────────────────────────────────
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOLS,
}));

// ── 툴 실행 핸들러 ─────────────────────────────────────────
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  switch (name) {
    case "example_tool": {
      const result = `처리 결과: ${args.input}`;
      return {
        content: [{ type: "text", text: result }],
      };
    }

    // case "another_tool": { ... }

    default:
      throw new Error(`알 수 없는 툴: ${name}`);
  }
});

// ── 실행 ──────────────────────────────────────────────────
const transport = new StdioServerTransport();
await server.connect(transport);
