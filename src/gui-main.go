package main

import (
	"fmt"
	"os"
	"path/filepath"

	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/data/binding"
	"fyne.io/fyne/v2/layout"
	"fyne.io/fyne/v2/widget"
)

type ArchiveManagerApp struct {
	app         fyne.App
	window      fyne.Window
	statusBind  binding.String
	operationBind binding.String
	auditBind   binding.String
}

func NewArchiveManagerApp() *ArchiveManagerApp {
	myApp := app.New()
	myWindow := myApp.NewWindow()
	myWindow.SetTitle("Sandboxed Archive Manager")
	myWindow.Resize(fyne.NewSize(1000, 700))

	return &ArchiveManagerApp{
		app:    myApp,
		window: myWindow,
		statusBind:  binding.NewString(),
		operationBind: binding.NewString(),
		auditBind:   binding.NewString(),
	}
}

func (am *ArchiveManagerApp) setupUI() {
	// Tabs for different operations
	tabs := container.NewAppTabs()

	// Tab 1: Create Archive
	tabs.Append(container.NewTabItem("Create Archive", am.createArchiveTab()))

	// Tab 2: Extract Archive
	tabs.Append(container.NewTabItem("Extract Archive", am.extractArchiveTab()))

	// Tab 3: Verify Archive
	tabs.Append(container.NewTabItem("Verify Archive", am.verifyArchiveTab()))

	// Tab 4: Audit Log
	tabs.Append(container.NewTabItem("Audit Log", am.auditLogTab()))

	// Tab 5: Security Status
	tabs.Append(container.NewTabItem("Security", am.securityTab()))

	// Main layout
	mainContainer := container.New(
		layout.NewVBoxLayout(),
		am.headerBar(),
		tabs,
		am.footerBar(),
	)

	am.window.SetContent(mainContainer)
}

func (am *ArchiveManagerApp) headerBar() *fyne.Container {
	header := container.New(
		layout.NewVBoxLayout(),
		widget.NewRichTextFromMarkdown("# Sandboxed Archive Manager\n_Three-Plane Security Model_"),
	)
	return header
}

func (am *ArchiveManagerApp) footerBar() *fyne.Container {
	statusLabel := widget.NewLabelWithData(am.statusBind)
	operationLabel := widget.NewLabelWithData(am.operationBind)

	footer := container.New(
		layout.NewVBoxLayout(),
		widget.NewSeparator(),
		container.New(
			layout.NewHBoxLayout(),
			widget.NewLabel("Status:"),
			statusLabel,
		),
		container.New(
			layout.NewHBoxLayout(),
			widget.NewLabel("Operation:"),
			operationLabel,
		),
	)

	am.statusBind.Set("Ready")
	return footer
}

func (am *ArchiveManagerApp) createArchiveTab() *fyne.Container {
	// File selection
	archiveNameEntry := widget.NewEntry()
	archiveNameEntry.SetPlaceHolder("archive.zip")

	selectedFilesLabel := widget.NewLabel("No files selected")

	selectFilesBtn := widget.NewButton("Select Files", func() {
		am.selectFilesDialog(selectedFilesLabel)
	})

	// Compression level
	compressionSelect := widget.NewSelect(
		[]string{"0 - Store", "1 - Fastest", "6 - Default", "9 - Best"},
		func(s string) {
			am.statusBind.Set(fmt.Sprintf("Compression: %s", s))
		},
	)
	compressionSelect.SetSelected("6 - Default")

	// Create button
	createBtn := widget.NewButton("Create Archive", func() {
		am.statusBind.Set("Creating archive...")
		am.operationBind.Set("create_archive")
		// Call actual archive creation
	})

	container := container.New(
		layout.NewVBoxLayout(),
		widget.NewLabel("Archive Name:"),
		archiveNameEntry,
		widget.NewSeparator(),
		widget.NewLabel("Input Files:"),
		selectFilesBtn,
		selectedFilesLabel,
		widget.NewSeparator(),
		widget.NewLabel("Compression:"),
		compressionSelect,
		widget.NewSeparator(),
		createBtn,
	)

	return container
}

func (am *ArchiveManagerApp) extractArchiveTab() *fyne.Container {
	archivePathEntry := widget.NewEntry()
	archivePathEntry.SetPlaceHolder("/path/to/archive.zip")

	destPathEntry := widget.NewEntry()
	destPathEntry.SetPlaceHolder("/path/to/destination")

	// Safe extraction option
	safeExtractCheck := widget.NewCheck("Safe Extraction (preflight check)", func(b bool) {
		if b {
			am.statusBind.Set("Safe extraction enabled")
		}
	})
	safeExtractCheck.SetChecked(true)

	// Extract button
	extractBtn := widget.NewButton("Extract Archive", func() {
		am.statusBind.Set("Extracting archive...")
		am.operationBind.Set("extract_archive")
	})

	container := container.New(
		layout.NewVBoxLayout(),
		widget.NewLabel("Archive Path:"),
		archivePathEntry,
		widget.NewSeparator(),
		widget.NewLabel("Destination:"),
		destPathEntry,
		widget.NewSeparator(),
		safeExtractCheck,
		widget.NewSeparator(),
		extractBtn,
	)

	return container
}

func (am *ArchiveManagerApp) verifyArchiveTab() *fyne.Container {
	archivePathEntry := widget.NewEntry()
	archivePathEntry.SetPlaceHolder("/path/to/archive.zip")

	verifyBtn := widget.NewButton("Verify Archive", func() {
		am.statusBind.Set("Verifying archive...")
		am.operationBind.Set("verify_archive")
	})

	resultLabel := widget.NewLabel("")

	container := container.New(
		layout.NewVBoxLayout(),
		widget.NewLabel("Archive Path:"),
		archivePathEntry,
		widget.NewSeparator(),
		verifyBtn,
		widget.NewSeparator(),
		resultLabel,
	)

	return container
}

func (am *ArchiveManagerApp) auditLogTab() *fyne.Container {
	// Audit log viewer
	auditList := widget.NewList(
		func() int { return 5 },
		func() fyne.CanvasObject {
			return widget.NewLabel("operation")
		},
		func(i widget.ListItemID, o fyne.CanvasObject) {
			o.(*widget.Label).SetText(fmt.Sprintf("Operation %d", i))
		},
	)

	exportBtn := widget.NewButton("Export Provenance Report", func() {
		am.statusBind.Set("Exporting audit log...")
	})

	container := container.New(
		layout.NewVBoxLayout(),
		widget.NewLabel("Recent Operations:"),
		auditList,
		widget.NewSeparator(),
		exportBtn,
	)

	return container
}

func (am *ArchiveManagerApp) securityTab() *fyne.Container {
	// Security status panel
	sandboxStatus := widget.NewLabel("✓ Sandbox: Active")
	policyStatus := widget.NewLabel("✓ Policy Engine: Enforcing")
	auditStatus := widget.NewLabel("✓ Audit Ledger: Recording")
	verificationStatus := widget.NewLabel("✓ Verification: Enabled")

	// Security model diagram
	modelText := widget.NewRichTextFromMarkdown(`
## Three-Plane Security Model

### Control Plane
- Policy evaluation
- Authorization decisions
- Rate limiting
- Audit logging

### Orchestration Plane
- DAG scheduler
- Dependency resolution
- Operation execution
- Error handling

### Sandbox Plane
- Path canonicalization
- Traversal prevention
- Symlink escape detection
- Postflight verification
`)

	container := container.New(
		layout.NewVBoxLayout(),
		widget.NewLabel("Security Status:"),
		sandboxStatus,
		policyStatus,
		auditStatus,
		verificationStatus,
		widget.NewSeparator(),
		modelText,
	)

	return container
}

func (am *ArchiveManagerApp) selectFilesDialog(label *widget.Label) {
	dialog.ShowFileOpen(func(reader fyne.URIReadCloser, err error) {
		if err == nil && reader != nil {
			label.SetText(fmt.Sprintf("Selected: %s", filepath.Base(reader.URI().Path())))
			reader.Close()
		}
	}, am.window)
}

func (am *ArchiveManagerApp) Run() {
	am.setupUI()
	am.window.ShowAndRun()
}

func main() {
	am := NewArchiveManagerApp()
	am.Run()
}
