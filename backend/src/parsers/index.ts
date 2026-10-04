import { BankEmailParser, ParsedTransaction } from '../types';
import { MandiriLivinParser } from './mandiri';
export { parseWithGeminiFallback } from './ai_fallback';

export class ParserRegistry {
  private parsers: BankEmailParser[] = [];

  constructor() {
    // Daftarkan parser bank di sini (bisa ditambah BCA, BRI, Jago, dll nantinya)
    this.parsers.push(new MandiriLivinParser());
  }

  parseEmail(messageId: string, from: string, subject: string, body: string): ParsedTransaction | null {
    for (const parser of this.parsers) {
      if (parser.canHandle(from, subject, body)) {
        const result = parser.parse(messageId, from, subject, body);
        if (result) return result;
      }
    }
    return null;
  }
}
