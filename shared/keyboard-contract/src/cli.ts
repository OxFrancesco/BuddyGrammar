import { join } from "node:path";

import { validateContractDirectory } from "./validate-contract";

const contractRoot = join(import.meta.dir, "..");
const report = await validateContractDirectory(contractRoot);

if (report.issues.length > 0) {
  for (const issue of report.issues) {
    console.error(`${issue.path} [${issue.code}] ${issue.message}`);
  }
  console.error(
    `Keyboard contract validation failed with ${report.issues.length} issue(s).`,
  );
  process.exitCode = 1;
} else {
  console.log(
    `Keyboard contract ${report.catalogRevision} is valid (${report.traceCaseCount} conformance cases).`,
  );
}
