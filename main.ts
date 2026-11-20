// Brainrot Bazaar — Snack Sprites: the hand-in program for make.fun's
// roblox-brainrot-01 bounty. Node 22, standard library only.
//
// The game itself is the Rojo project in this directory: build it first with
//   /home/hatch/workspace/bin/rojo build default.project.json --output game.rbxl
// and this program copies the built place, the Luau sources, the screenshots and
// PLAY.json into the output directory, then writes dossier.json — the summary
// the judge reads — with the vendored make.fun library.
//
// The grader's container gives the output directory as /output. Outside it,
// MAKEFUN_OUTPUT_DIR stands in:
//   mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts
//
// The grader refuses any name under the output that does not start with a
// letter, a digit or _ and holds only letters, digits, . _ and -. A stray
// .gitkeep or .DS_Store anywhere under it fails the entry, so the directory
// copies below skip every name that starts with a dot, at any depth.

import { copyFileSync, cpSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDossier } from './vendor/makefun-roblox.ts';

// The repository root is the directory this file lives in.
const repoRoot = fileURLToPath(new URL('.', import.meta.url));

// /output in the grader; MAKEFUN_OUTPUT_DIR anywhere else.
const outputDir = process.env.MAKEFUN_OUTPUT_DIR ?? '/output';

// cpSync filter: keep out every file and directory whose name starts with a dot.
const isNotDotted = (path: string): boolean => !basename(path).startsWith('.');

// The built place and the published-place record go in as single files.
copyFileSync(join(repoRoot, 'game.rbxl'), join(outputDir, 'game.rbxl'));
copyFileSync(join(repoRoot, 'PLAY.json'), join(outputDir, 'PLAY.json'));

// The sources and the screenshots go in as whole directories.
cpSync(join(repoRoot, 'src'), join(outputDir, 'src'), { recursive: true, filter: isNotDotted });
mkdirSync(join(outputDir, 'screenshots'), { recursive: true });
if (existsSync(join(repoRoot, 'screenshots'))) {
  cpSync(join(repoRoot, 'screenshots'), join(outputDir, 'screenshots'), { recursive: true, filter: isNotDotted });
}

// The dossier, built by the kit's vendored library from what is now in the
// output directory. The caps mirror the scorer's own gate: at most 4
// screenshots, none over 256 KiB; a place of at most 500,000 instances; scripts
// whose sources come to at most 8 MiB and whose paths come to at most 1,048,576
// characters in all. text_max_bytes is the only cap that shapes the bytes.
writeFileSync(
  join(outputDir, 'dossier.json'),
  buildDossier(outputDir, {
    text_max_bytes: 65536,
    screenshots: { max: 4, max_bytes: 262144 },
    max_instances: 500000,
    scripts_max_source_bytes: 8388608,
    scripts_max_path_chars: 1048576,
  }),
);
