// Package standards embeds the engineering governance files for use by Go projects.
// Consumers can call Materialize to extract the files to a local directory,
// or read them directly via the Governance filesystem.
package standards

import "embed"

// Governance exposes the governance markdown files as an embedded filesystem.
//
//go:embed ../governance/*.md
var Governance embed.FS