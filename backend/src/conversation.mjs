import { randomUUID } from "node:crypto";

const ID_PATTERN = /^conv_[a-z0-9_-]{8,64}$/;
const MAX_MESSAGES = 40;

export class ConversationError extends Error {
  constructor(message, code = "invalid_conversation") {
    super(message);
    this.name = "ConversationError";
    this.code = code;
  }
}

export class ConversationStore {
  constructor({ maxConversations = 200, maxMessages = MAX_MESSAGES } = {}) {
    this.maxConversations = maxConversations;
    this.maxMessages = maxMessages;
    this.conversations = new Map();
  }

  create(ownerId = "owner_local") {
    const conversation = {
      id: `conv_${randomUUID()}`,
      ownerId,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      messages: [],
      tasks: [],
      entities: {}
    };
    this.conversations.set(conversation.id, conversation);
    this.#evict();
    return conversation;
  }

  ensure(conversationId, ownerId = "owner_local") {
    if (conversationId === undefined || conversationId === null || conversationId === "") {
      return { conversation: this.create(ownerId), created: true };
    }
    if (typeof conversationId !== "string" || !ID_PATTERN.test(conversationId)) {
      throw new ConversationError("conversationId 格式非法", "invalid_conversation_id");
    }
    const existing = this.conversations.get(conversationId);
    if (existing) {
      if ((existing.ownerId ?? "owner_local") !== ownerId) {
        throw new ConversationError("无权访问该会话", "forbidden_conversation");
      }
      return { conversation: existing, created: false };
    }
    const conversation = {
      id: conversationId,
      ownerId,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      messages: [],
      tasks: [],
      entities: {}
    };
    this.conversations.set(conversationId, conversation);
    this.#evict();
    return { conversation, created: true };
  }

  get(conversationId) {
    return this.conversations.get(conversationId) ?? null;
  }

  append(conversationId, messages) {
    const conversation = this.#require(conversationId);
    for (const message of messages ?? []) {
      if (!message || !["user", "assistant"].includes(message.role)) continue;
      const content = typeof message.content === "string" ? message.content.trim() : "";
      if (!content) continue;
      conversation.messages.push({ role: message.role, content, at: new Date().toISOString() });
    }
    conversation.messages = conversation.messages.slice(-this.maxMessages);
    conversation.updatedAt = new Date().toISOString();
  }

  transcript(conversationId, { limit = 10, excludeLatestUser = false } = {}) {
    const conversation = this.conversations.get(conversationId);
    if (!conversation) return [];
    const messages = conversation.messages.slice();
    if (excludeLatestUser && messages.at(-1)?.role === "user") messages.pop();
    return messages.slice(-limit).map((message) => ({ role: message.role, content: message.content }));
  }

  tasks(conversationId) {
    return (this.conversations.get(conversationId)?.tasks ?? []).map((task) => ({ ...task }));
  }

  upsertTask(conversationId, task) {
    const conversation = this.#require(conversationId);
    const existing = conversation.tasks.find((item) => item.taskId === task.taskId);
    if (existing) {
      Object.assign(existing, task, { updatedAt: new Date().toISOString() });
    } else {
      conversation.tasks.push({ ...task, updatedAt: new Date().toISOString() });
    }
    conversation.updatedAt = new Date().toISOString();
  }

  closeTask(conversationId, taskId, state) {
    const conversation = this.conversations.get(conversationId);
    if (!conversation) return;
    const task = conversation.tasks.find((item) => item.taskId === taskId);
    if (!task) return;
    task.state = state;
    task.updatedAt = new Date().toISOString();
    conversation.updatedAt = new Date().toISOString();
  }

  setEntities(conversationId, patch) {
    const conversation = this.conversations.get(conversationId);
    if (!conversation) return;
    conversation.entities = { ...conversation.entities, ...patch };
    conversation.updatedAt = new Date().toISOString();
  }

  summary(conversationId, ownerId) {
    const conversation = this.conversations.get(conversationId);
    if (!conversation) return null;
    if (ownerId && (conversation.ownerId ?? "owner_local") !== ownerId) {
      throw new ConversationError("无权访问该会话", "forbidden_conversation");
    }
    return {
      id: conversation.id,
      createdAt: conversation.createdAt,
      updatedAt: conversation.updatedAt,
      messages: conversation.messages.map((message) => ({ ...message })),
      tasks: conversation.tasks.map((task) => ({ ...task })),
      entities: structuredClone(conversation.entities)
    };
  }

  reset(conversationId, ownerId) {
    const conversation = this.conversations.get(conversationId);
    if (conversation && ownerId && (conversation.ownerId ?? "owner_local") !== ownerId) {
      throw new ConversationError("无权访问该会话", "forbidden_conversation");
    }
    return this.conversations.delete(conversationId);
  }

  #require(conversationId) {
    const conversation = this.conversations.get(conversationId);
    if (!conversation) throw new ConversationError("未知会话", "unknown_conversation");
    return conversation;
  }

  #evict() {
    while (this.conversations.size > this.maxConversations) {
      const oldest = [...this.conversations.values()].sort((a, b) => a.updatedAt.localeCompare(b.updatedAt))[0];
      this.conversations.delete(oldest.id);
    }
  }
}
