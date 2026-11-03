import { Notice, Plugin, TFile } from 'obsidian';
import { splitTrailingAgentBlocks, unwrapAgentBlocks } from './blocks';
import { reviewHash, splitFrontmatter, trustState, type TrustState } from './hash';

const STATE_LABEL: Record<Exclude<TrustState, 'none'>, string> = {
	unreviewed: 'SB: unreviewed',
	reviewed: 'SB: reviewed',
	'changed-since-review': 'SB: changed since review',
	'agent-blocks-pending': 'SB: agent blocks pending',
};

function today(): string {
	const d = new Date();
	const pad = (n: number) => String(n).padStart(2, '0');
	return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export default class SecondBrainCompanion extends Plugin {
	private statusEl: HTMLElement | null = null;
	private statusSeq = 0;

	onload() {
		// Hidden by Obsidian on mobile; there each command's Notice reports the state instead.
		this.statusEl = this.addStatusBarItem();
		const refresh = () => void this.refreshStatus();
		this.registerEvent(this.app.workspace.on('active-leaf-change', refresh));
		this.registerEvent(
			this.app.metadataCache.on('changed', (file) => {
				if (file.path === this.app.workspace.getActiveFile()?.path) refresh();
			}),
		);
		this.app.workspace.onLayoutReady(refresh);

		this.addNoteCommand('mark-reviewed', 'Mark as reviewed', async (file) => {
			const hash = await this.markReviewed(file);
			new Notice(`Marked as reviewed (${hash})`);
		});
		this.addNoteCommand('accept-agent-blocks', 'Accept agent blocks', (file) => this.acceptAgentBlocks(file));
		this.addNoteCommand('toggle-protected', 'Toggle protected', (file) => this.toggleProtected(file));
	}

	private async refreshStatus(): Promise<void> {
		const seq = ++this.statusSeq;
		const el = this.statusEl;
		if (!el) return;
		const file = this.app.workspace.getActiveFile();
		let state: TrustState = 'none';
		if (file) {
			const text = await this.app.vault.cachedRead(file);
			const fm: Record<string, unknown> = { ...(this.app.metadataCache.getFileCache(file)?.frontmatter ?? {}) };
			state = await trustState(text, fm, file.path);
		}
		if (seq !== this.statusSeq) return; // a newer refresh superseded this one
		el.setText(state === 'none' ? '' : STATE_LABEL[state]);
		el.toggleClass('sbc-hidden', state === 'none');
	}

	private addNoteCommand(id: string, name: string, run: (file: TFile) => Promise<void>) {
		this.addCommand({
			id,
			name,
			checkCallback: (checking: boolean) => {
				const file = this.app.workspace.getActiveFile();
				if (!file || file.extension !== 'md') return false;
				if (!checking) {
					run(file).then(() => this.refreshStatus()).catch((err: unknown) => {
						console.error(`[second-brain-companion] ${id} failed`, err);
						new Notice(`Second Brain Companion: ${id} failed, see the console.`);
					});
				}
				return true;
			},
		});
	}

	/** Pins the review: `reviewed` (today) and `reviewed_hash` of the current review body. */
	private async markReviewed(file: TFile): Promise<string> {
		const hash = await reviewHash(await this.app.vault.read(file));
		await this.app.fileManager.processFrontMatter(file, (fm: Record<string, unknown>) => {
			fm.reviewed = today();
			fm.reviewed_hash = hash;
		});
		return hash;
	}

	private async acceptAgentBlocks(file: TFile): Promise<void> {
		const text = await this.app.vault.read(file);
		const { blocks } = splitTrailingAgentBlocks(splitFrontmatter(text).body);
		if (blocks.length === 0) {
			new Notice('No agent blocks in this note.');
			return;
		}
		await this.app.vault.process(file, unwrapAgentBlocks);
		const hash = await this.markReviewed(file);
		new Notice(`Accepted ${blocks.length} agent block(s) and marked as reviewed (${hash})`);
	}

	private async toggleProtected(file: TFile): Promise<void> {
		let now = false;
		await this.app.fileManager.processFrontMatter(file, (fm: Record<string, unknown>) => {
			if (fm.protected === true || fm.protected === 'true') {
				delete fm.protected;
			} else {
				fm.protected = true;
				now = true;
			}
		});
		new Notice(now ? 'Protected: on' : 'Protected: off');
	}
}
