$ErrorActionPreference = 'Stop'

# Load only the helper's AST. Never execute the build script's top-level code,
# signing setup, project discovery, Flutter commands, or environment handling.
$tokens = $null
$parseErrors = $null
$buildPath = Join-Path $PSScriptRoot 'build_karaok.ps1'
$ast = [Management.Automation.Language.Parser]::ParseFile($buildPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw "Build script parse errors: $parseErrors" }
$helpers = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Test-KaraOkDarkTheme'
}, $false))
if ($helpers.Count -ne 1) { throw 'Expected exactly one dark-theme checker.' }
. ([scriptblock]::Create($helpers[0].Extent.Text))

$fixtures = @(
    @{ Name = 'Dark ThemeData'; Dark = $true; Source = 'ThemeData(brightness: Brightness.dark)' }
    @{ Name = 'Dark ColorScheme'; Dark = $true; Source = 'ColorScheme(brightness: Brightness.dark)' }
    @{ Name = 'Dark named constructor'; Dark = $true; Source = 'ColorScheme.fromSeed(seedColor: Color(0xff00cdb5), brightness: Brightness.dark)' }
    @{ Name = 'Nested dark scheme'; Dark = $true; Source = 'ThemeData(brightness: Brightness.light, colorScheme: ColorScheme.fromSeed(brightness: Brightness.dark))' }
    @{ Name = 'Arguments after nested parentheses'; Dark = $true; Source = 'ThemeData(textTheme: makeText(scale(1.3)), brightness: Brightness.dark)' }
    @{ Name = 'Comments between tokens'; Dark = $true; Source = 'ThemeData(brightness /* why */ : Brightness /* mode */ . dark)' }
    @{ Name = 'Multiple constructors'; Dark = $true; Source = 'ThemeData(brightness: Brightness.light); ThemeData(brightness: Brightness.dark);' }
    @{ Name = 'Light constructors'; Dark = $false; Source = 'ThemeData(brightness: Brightness.light, colorScheme: ColorScheme.fromSeed(brightness: Brightness.light))' }
    @{ Name = 'Icons-only light fixture'; Dark = $false; Source = @'
ThemeData(
  brightness: Brightness.light,
  appBarTheme: AppBarTheme(
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  ),
  colorScheme: ColorScheme.fromSeed(brightness: Brightness.light),
)
'@ }
    @{ Name = 'Other constructor brightness'; Dark = $false; Source = 'ThemeData(appBarTheme: Other(brightness: Brightness.dark), brightness: Brightness.light)' }
    @{ Name = 'After closed constructor'; Dark = $false; Source = 'ThemeData(textTheme: nested()); Other(brightness: Brightness.dark);' }
    @{ Name = 'Closure inside constructor'; Dark = $false; Source = 'ThemeData(builder: () { return Other(brightness: Brightness.dark); })' }
    @{ Name = 'Identifier suffixes'; Dark = $false; Source = 'OtherThemeData(brightness: Brightness.dark); OtherColorScheme(brightness: Brightness.dark);' }
    @{ Name = 'Line and nested block comments'; Dark = $false; Source = @'
// ThemeData(brightness: Brightness.dark)
/* outer /* nested */ ColorScheme(brightness: Brightness.dark) */
ThemeData(brightness: Brightness.light)
'@ }
    @{ Name = 'Strings and raw multiline strings'; Dark = $false; Source = @'
final a = "ThemeData(brightness: Brightness.dark)";
final b = 'ColorScheme(brightness: Brightness.dark)';
final c = r'''ThemeData(brightness: Brightness.dark)''';
final d = """ColorScheme(brightness: Brightness.dark)""";
ThemeData(brightness: Brightness.light)
'@ }
    @{ Name = 'Quoted parentheses do not close scope'; Dark = $true; Source = 'ThemeData(debugLabel: ")", brightness: Brightness.dark)' }
    @{ Name = 'Empty source'; Dark = $false; Source = '' }
)

foreach ($fixture in $fixtures) {
    $actual = Test-KaraOkDarkTheme -Source $fixture.Source
    if ($actual -isnot [bool] -or $actual -ne $fixture.Dark) {
        throw "$($fixture.Name): expected $($fixture.Dark), got $actual"
    }
    Write-Output "PASS: $($fixture.Name)"
}
Write-Output "$($fixtures.Count) theme-check fixtures passed. No build was executed."
