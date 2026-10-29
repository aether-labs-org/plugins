export const log = {
  info(message: string, fields: object = {}): void {
    process.stdout.write(JSON.stringify({ level: "info", message, ...fields }) + "\n");
  },
};
