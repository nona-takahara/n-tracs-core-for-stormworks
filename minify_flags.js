// storm-lua-minify に渡すフラグ

// 本番ビルドのフラグ
const MINIFY_FLAGS = [
    "-m",
    "--assume-closed-field-names",
    ...["ui_id", "cheatBattery", "recommendedSettings", "webCtc", "webCtcPort"].flatMap((n) => ["--never-rename-field", n]),
    "--constant-optimizations",
    "--global-renaming",
];

// 比較のテストのフラグ
const REFERENCE_FLAGS = [
    "-m",
    "--no-field-renaming", "--no-global-renaming",
    "--no-constant-expression-evaluation", "--no-local-constant-propagation", "--no-interprocedural-constant-propagation",
];

module.exports = { MINIFY_FLAGS, REFERENCE_FLAGS };
