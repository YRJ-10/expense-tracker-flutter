export interface Env {
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
  FIREBASE_PROJECT_ID: string;
  FIREBASE_CLIENT_EMAIL: string;
  FIREBASE_PRIVATE_KEY: string;
  WORKER_AUTH_TOKEN?: string;
  ENVIRONMENT?: string;
}

export interface ParsedTransaction {
  bank: string;
  accountNumber?: string;
  type: 'expense' | 'income';
  amount: number;
  date: string; // ISO String
  description: string;
  category: string;
  referenceId: string;
  messageId: string;
  rawSnippet?: string;
}

export interface BankEmailParser {
  bankName: string;
  canHandle(from: string, subject: string, body: string): boolean;
  parse(messageId: string, from: string, subject: string, htmlOrText: string): ParsedTransaction | null;
}
