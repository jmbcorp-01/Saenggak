import { TranslateClient, TranslateTextCommand } from '@aws-sdk/client-translate';
import type { Translator } from './ports.js';

/** Feed translation with Amazon Translate. Results are cached in the database. */
export class AwsTranslator implements Translator {
  constructor(private readonly client = new TranslateClient({})) {}

  async translate(text: string, from: string, to: string): Promise<string> {
    const out = await this.client.send(
      new TranslateTextCommand({ Text: text, SourceLanguageCode: from, TargetLanguageCode: to }),
    );
    return out.TranslatedText ?? text;
  }
}
