# Changelog

## [1.3.0](https://github.com/coryparrry/Foundation-Eval-Labs/compare/v1.2.0...v1.3.0) (2026-09-08)


### Features

* **codex:** add guided MCP connector setup ([d24ccc1](https://github.com/coryparrry/Foundation-Eval-Labs/commit/d24ccc1b1dc62f639fff68564975d97e9c68bc50))
* **evals:** add Foundation Models controls ([bf2a5d6](https://github.com/coryparrry/Foundation-Eval-Labs/commit/bf2a5d638e355253f472ef4f40509508e245e101))
* **evals:** add standalone Foundation Models runner ([ef40462](https://github.com/coryparrry/Foundation-Eval-Labs/commit/ef40462a340397be37d4ee7523e8f1a56942917c))
* **evals:** compare saved runs and inspect measured traces ([6e40337](https://github.com/coryparrry/Foundation-Eval-Labs/commit/6e403374547daec9d9f5c4e50c1781ecdb4c037d))
* **evals:** exercise custom tools and dynamic profiles ([37db4a1](https://github.com/coryparrry/Foundation-Eval-Labs/commit/37db4a1ed1bafc688d0e488e6f7e054df16e9ee2))
* **evals:** make suite and run persistence durable ([3c977c3](https://github.com/coryparrry/Foundation-Eval-Labs/commit/3c977c348b75047cb9d1019b1bd6d0ba8b6ccd6f))
* **mcp:** add dual-protocol eval control server ([535b71f](https://github.com/coryparrry/Foundation-Eval-Labs/commit/535b71f993f54667d407dace0df26e086ae97c2a))
* **release:** add manually controlled signed GitHub releases ([#8](https://github.com/coryparrry/Foundation-Eval-Labs/issues/8)) ([843e3e1](https://github.com/coryparrry/Foundation-Eval-Labs/commit/843e3e1f6afef2fd5c6cacfa2c3a1f1ca91a0866))
* **traces:** add a native workflow waterfall and inspector ([#19](https://github.com/coryparrry/Foundation-Eval-Labs/issues/19)) ([bf350d2](https://github.com/coryparrry/Foundation-Eval-Labs/commit/bf350d2afcde6d1cb695a35cf24653e4f057e6c7))
* **ui:** refine evaluation workflow ([24cc10e](https://github.com/coryparrry/Foundation-Eval-Labs/commit/24cc10e72d525b1761363d6fb824c2ddb99fde24))


### Bug Fixes

* **app:** add release icon and dmg installation instructions ([4fac7b9](https://github.com/coryparrry/Foundation-Eval-Labs/commit/4fac7b940c3ce7f3f0ee72a63bf4e311e279e84c))
* **app:** add signed updates and private launch statistics ([#16](https://github.com/coryparrry/Foundation-Eval-Labs/issues/16)) ([2353a78](https://github.com/coryparrry/Foundation-Eval-Labs/commit/2353a78657776a4f1df0026ee90d0b18330f03d4))
* **docs:** make the README artwork a full-width banner ([#5](https://github.com/coryparrry/Foundation-Eval-Labs/issues/5)) ([cfff5cc](https://github.com/coryparrry/Foundation-Eval-Labs/commit/cfff5ccfbaf9e890c18dd7b0040b10c9541453d2))
* **evals:** address concurrency warnings and refresh lifecycle checks ([#11](https://github.com/coryparrry/Foundation-Eval-Labs/issues/11)) ([4a86219](https://github.com/coryparrry/Foundation-Eval-Labs/commit/4a86219328c7827a3afc539e73daea37aabf1a52))
* **evals:** require complete semantic judge assessments ([fe6de3e](https://github.com/coryparrry/Foundation-Eval-Labs/commit/fe6de3e15e05b471d8b9ea88c111ffeae86f2f8a))
* **evals:** stabilize generation and saved drafts ([456fe95](https://github.com/coryparrry/Foundation-Eval-Labs/commit/456fe9527ca9c6d9deb8c1e68c90b2ce2f127e4f))
* **evals:** trust exact rubric references ([accc5e9](https://github.com/coryparrry/Foundation-Eval-Labs/commit/accc5e98b4d339eac74cbae388d3181e4c127f13))
* **evals:** validate judge evidence and score exact rules ([2dac2d0](https://github.com/coryparrry/Foundation-Eval-Labs/commit/2dac2d0fff93dc152ddda7d88ac0533a5af1b5c3))
* **mcp:** accept valid Codex TOML layouts ([64a6a5d](https://github.com/coryparrry/Foundation-Eval-Labs/commit/64a6a5d7dccf2e5c0f4fa3be7fb28ae6d337d61a))
* **mcp:** close acceptance contract gaps ([e536ef4](https://github.com/coryparrry/Foundation-Eval-Labs/commit/e536ef4829ba0de8005fad19bade5652a4dcfb6e))
* **mcp:** expose connector installation settings ([6fad4a7](https://github.com/coryparrry/Foundation-Eval-Labs/commit/6fad4a76cac89f3107d0b51d6bdafe07f8b901ce))
* **mcp:** keep state snapshots authoritative ([a017934](https://github.com/coryparrry/Foundation-Eval-Labs/commit/a017934b923f71b50f7358fc7dcbf9d5abdc50c8))
* **mcp:** recover stopped listeners and report resource errors ([1e42c5e](https://github.com/coryparrry/Foundation-Eval-Labs/commit/1e42c5e79a6aeff2a52120ff54741775e2213a87))
* **mcp:** remove sandboxed Codex setup ([b4a972a](https://github.com/coryparrry/Foundation-Eval-Labs/commit/b4a972af17578481c86b07c317416aa9d8bedb09))
* **mcp:** simplify Codex connector setup ([7313995](https://github.com/coryparrry/Foundation-Eval-Labs/commit/7313995d2ac75ce16d68ffe4cffc24d23307aea0))
* **mcp:** simplify local Codex connection ([bc9bb25](https://github.com/coryparrry/Foundation-Eval-Labs/commit/bc9bb25d3bdf42775b06973530def9911d57e8f2))
* prepare source and recovery paths for open-source release ([c038f52](https://github.com/coryparrry/Foundation-Eval-Labs/commit/c038f5241e99e64c1ae4c22e5c2dc0385fdc3935))
* **release:** automate release PRs on main merges ([#12](https://github.com/coryparrry/Foundation-Eval-Labs/issues/12)) ([a4c856b](https://github.com/coryparrry/Foundation-Eval-Labs/commit/a4c856bd5649e126bc61c8a0bac6d9970c870277))
* **release:** publish releases only after verified DMG upload ([#14](https://github.com/coryparrry/Foundation-Eval-Labs/issues/14)) ([014d9e5](https://github.com/coryparrry/Foundation-Eval-Labs/commit/014d9e58e8f3ec8757b52c06fb72e789ce89794a))
* **results:** reset filters and choose compatible baselines ([6f75c77](https://github.com/coryparrry/Foundation-Eval-Labs/commit/6f75c7717817f28f090b552b3fba9eaacebcf8d7))
* **scoring:** expose expected text inputs ([cd7a72d](https://github.com/coryparrry/Foundation-Eval-Labs/commit/cd7a72d6d6cd667d221a077f1e7b5808722f6d52))
* **scoring:** make evaluation rubrics actionable ([2fa9413](https://github.com/coryparrry/Foundation-Eval-Labs/commit/2fa94133be49c70bfab5c7e2b9da0519d22f4e0c))
* strengthen CI and add repository branding ([#3](https://github.com/coryparrry/Foundation-Eval-Labs/issues/3)) ([73f2d8c](https://github.com/coryparrry/Foundation-Eval-Labs/commit/73f2d8c7bb7d536cb80d54d4be45d3fdfe2439dc))
* **ui:** give evaluations a distinct workbench layout ([6cf85ac](https://github.com/coryparrry/Foundation-Eval-Labs/commit/6cf85ac359efd59c6839fb5fb55f0b787c0d8c3e))
* **ui:** keep suite editor within its window ([9ceeb9e](https://github.com/coryparrry/Foundation-Eval-Labs/commit/9ceeb9ec9a21fbe30c896a0484ae5695007624a0))
* **ui:** reshape the evaluation workbench around summary cards ([#6](https://github.com/coryparrry/Foundation-Eval-Labs/issues/6)) ([d5469ea](https://github.com/coryparrry/Foundation-Eval-Labs/commit/d5469eaaf7067710914bc2a51b290ca4441d6dfc))
* **ui:** restore native selection and system accents ([dbe6f79](https://github.com/coryparrry/Foundation-Eval-Labs/commit/dbe6f794db66658e623888e2d2e0aae0e130c072))
* **ui:** restore readable sidebar layout ([482153d](https://github.com/coryparrry/Foundation-Eval-Labs/commit/482153d0512b9eb76deb182aa074488128bb8fb6))
* **ui:** widen the sidebar slightly ([e2c97b0](https://github.com/coryparrry/Foundation-Eval-Labs/commit/e2c97b073a6280ff2f31e09cd2025538708dc7cb))
* **updates:** enable automatic Sparkle updates ([#17](https://github.com/coryparrry/Foundation-Eval-Labs/issues/17)) ([b0a5b70](https://github.com/coryparrry/Foundation-Eval-Labs/commit/b0a5b709f827d4597ca71e5499ce95133b3222c2))

## [1.2.0](https://github.com/coryparrry/Foundation-Eval-Labs/compare/v1.1.1...v1.2.0) (2026-09-08)


### Features

* **traces:** add a native workflow waterfall and inspector ([#19](https://github.com/coryparrry/Foundation-Eval-Labs/issues/19)) ([bf350d2](https://github.com/coryparrry/Foundation-Eval-Labs/commit/bf350d2afcde6d1cb695a35cf24653e4f057e6c7))

## [1.1.1](https://github.com/coryparrry/Foundation-Eval-Labs/compare/v1.1.0...v1.1.1) (2026-09-06)


### Bug Fixes

* **app:** add signed updates and private launch statistics ([#16](https://github.com/coryparrry/Foundation-Eval-Labs/issues/16)) ([2353a78](https://github.com/coryparrry/Foundation-Eval-Labs/commit/2353a78657776a4f1df0026ee90d0b18330f03d4))
* **updates:** enable automatic Sparkle updates ([#17](https://github.com/coryparrry/Foundation-Eval-Labs/issues/17)) ([b0a5b70](https://github.com/coryparrry/Foundation-Eval-Labs/commit/b0a5b709f827d4597ca71e5499ce95133b3222c2))

## [1.1.0](https://github.com/coryparrry/Foundation-Eval-Labs/compare/v1.0.0...v1.1.0) (2026-09-06)


### Features

* **release:** add manually controlled signed GitHub releases ([#8](https://github.com/coryparrry/Foundation-Eval-Labs/issues/8)) ([843e3e1](https://github.com/coryparrry/Foundation-Eval-Labs/commit/843e3e1f6afef2fd5c6cacfa2c3a1f1ca91a0866))


### Bug Fixes

* **docs:** make the README artwork a full-width banner ([#5](https://github.com/coryparrry/Foundation-Eval-Labs/issues/5)) ([cfff5cc](https://github.com/coryparrry/Foundation-Eval-Labs/commit/cfff5ccfbaf9e890c18dd7b0040b10c9541453d2))
* **evals:** address concurrency warnings and refresh lifecycle checks ([#11](https://github.com/coryparrry/Foundation-Eval-Labs/issues/11)) ([4a86219](https://github.com/coryparrry/Foundation-Eval-Labs/commit/4a86219328c7827a3afc539e73daea37aabf1a52))
* **release:** automate release PRs on main merges ([#12](https://github.com/coryparrry/Foundation-Eval-Labs/issues/12)) ([a4c856b](https://github.com/coryparrry/Foundation-Eval-Labs/commit/a4c856bd5649e126bc61c8a0bac6d9970c870277))
* **release:** publish releases only after verified DMG upload ([#14](https://github.com/coryparrry/Foundation-Eval-Labs/issues/14)) ([014d9e5](https://github.com/coryparrry/Foundation-Eval-Labs/commit/014d9e58e8f3ec8757b52c06fb72e789ce89794a))
* strengthen CI and add repository branding ([#3](https://github.com/coryparrry/Foundation-Eval-Labs/issues/3)) ([73f2d8c](https://github.com/coryparrry/Foundation-Eval-Labs/commit/73f2d8c7bb7d536cb80d54d4be45d3fdfe2439dc))
* **ui:** reshape the evaluation workbench around summary cards ([#6](https://github.com/coryparrry/Foundation-Eval-Labs/issues/6)) ([d5469ea](https://github.com/coryparrry/Foundation-Eval-Labs/commit/d5469eaaf7067710914bc2a51b290ca4441d6dfc))
