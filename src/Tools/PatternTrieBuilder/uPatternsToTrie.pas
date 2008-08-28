(*
    This file is part of Dxbx - a XBox emulator written in Delphi (ported over from cxbx)
    Copyright (C) 2007 Shadow_tj and other members of the development team.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*)
unit uPatternsToTrie;

{$INCLUDE ..\..\Dxbx.inc}

interface

uses
  // Delphi
  Windows, // ERROR_SUCCESS
  SysUtils, // CompareStr, FreeAndNil
  Classes, // TList
  Contnrs, // TObjectList
  Math, // Min
  // Dxbx
  uDxbxUtils,
  uXboxLibraryUtils,
  uStoredTrieTypes;

type
  TPattern = array of Word;

  TPatternTrieLeaf = class; // forward

  PVersionedXboxLibraryFunction = ^RVersionedXboxLibraryFunction;
  RVersionedXboxLibraryFunction = record
    VersionedXboxLibrary: PVersionedXboxLibrary;
    Name: string;
    CRCLength: Byte;
    CRCValue: Word;
    TotalLength: Word;
  end;

  TPatternTrieNode = class(TObject)
  protected
    MyChildren: TObjectList;
    function GetChild(const Index: Integer): TPatternTrieNode;
    function GetNrChildren: Integer;
    function FindLongestMatchingChild(const aFunctionPattern: TPattern; const aPatternOffset: Integer; out MatchLen: Integer): TPatternTrieNode;
    function SplitBeforeOffset(const aSplitOffset: Integer): TPatternTrieNode;
    function AddChild(const aFunctionPattern: TPattern; const aPatternOffset: Integer): TPatternTrieNode;
    function AddLeaf(const aFunction: PVersionedXboxLibraryFunction): Boolean;
    function NodeAsString: string; virtual;
  public
    Pattern: TPattern;

    property NrChildren: Integer read GetNrChildren;
    property Children[const Index: Integer]: TPatternTrieNode read GetChild;

    constructor Create;
    destructor Destroy; override;

    function AddPattern(const aFunction: PVersionedXboxLibraryFunction; const aFunctionPattern: TPattern; const aPatternOffset: Integer): TPatternTrieNode;
  end;

  TPatternTrieLeaf = class(TPatternTrieNode)
  public
    LeafNr: Integer;
    VersionedXboxLibraryFunction: PVersionedXboxLibraryFunction;
    function NodeAsString: string; override;
  end;

  TPatternTrie = class(TPatternTrieNode)
  public
    VersionedFunctions: TList;
    VersionedLibraries: TList;

    function NodeAsString: string; override;
    procedure Sort;
    procedure Dump(const aOutput: TStrings);
    procedure Save(const aFileName: string);
  end;

procedure PatternToTrie_Main;

implementation

const
  // TODO : Make these a command-line option :
  DumpFileName = string('TrieDump.txt');
  StoredTrieFileName = string('StoredTrie.dpt'); // Dxbx Pattern Trie
  StoredTrieTestFileName = string(StoredTrieFileName + '.txt');
  
function PatternTrie_NodeCompare(Node1, Node2: TPatternTrieNode): Integer;
var
  i, Len: Integer;
begin
  // Determine the length of the shortest of the two patterns :
  Len := Min(Length(Node1.Pattern), Length(Node2.Pattern));
  // Loop over the first part of the pattern, which is present in both :
  for i := 0 to Len - 1 do
  begin
    // Compare every byte (well, actually word - because of the DontCareValue) :
    Result := Node1.Pattern[i] - Node2.Pattern[i];
    // Stop on a mismatch :
    if Result <> 0 then
      Exit;
  end;

  // This case can't happen in a radix trie, but implement it anyway :
  Result := Length(Node1.Pattern) - Length(Node2.Pattern);
end;

function PatternTrie_LeafCompare(Leaf1, Leaf2: TPatternTrieLeaf): Integer;
begin
  // Order leafs on their function name first :
  Result := CompareStr(Leaf1.VersionedXboxLibraryFunction.Name,
                       Leaf2.VersionedXboxLibraryFunction.Name);
  if Result <> 0 then
    Exit;

  // Next, order them on the name of the library they're in :
  Result := CompareStr(Leaf1.VersionedXboxLibraryFunction.VersionedXboxLibrary.LibName,
                       Leaf2.VersionedXboxLibraryFunction.VersionedXboxLibrary.LibName);
  if Result <> 0 then
    Exit;

  // And last, order these by the version of the library :
  Result := Leaf1.VersionedXboxLibraryFunction.VersionedXboxLibrary.LibVersion -
            Leaf2.VersionedXboxLibraryFunction.VersionedXboxLibrary.LibVersion;
end;

{ TPatternTrieNode }

constructor TPatternTrieNode.Create;
begin
  inherited Create;

  MyChildren := TObjectList.Create({OwnsObjects=}True);
end;

destructor TPatternTrieNode.Destroy;
begin
  FreeAndNil(MyChildren);

  inherited Destroy;
end;

function TPatternTrieNode.GetNrChildren: Integer;
begin
  Result := MyChildren.Count;
end;

function TPatternTrieNode.GetChild(const Index: Integer): TPatternTrieNode;
begin
  Result := TPatternTrieNode(MyChildren[Index]);
end;

function TPatternTrieNode.FindLongestMatchingChild(
  const aFunctionPattern: TPattern;
  const aPatternOffset: Integer;
  out MatchLen: Integer): TPatternTrieNode;
var
  i, j: Integer;
  Child: TPatternTrieNode;
begin
  // Search in all children :
  for i := 0 to NrChildren - 1 do
  begin
    Child := Children[i];

    // Count how many elements match :
    j := 0;
    while (j < Length(Child.Pattern))
      and (Child.Pattern[j] = aFunctionPattern[aPatternOffset + j]) do
        Inc(j);

    // As soon as we have a match, we return that (the structure of the
    // trie prevents getting more matches, so we can stop searching) : 
    if j > 0 then
    begin
      Result := Child;
      MatchLen := j;
      Exit;
    end;
  end;

  // Return nothing found :
  Result := nil;
  MatchLen := 0;
end;

function TPatternTrieNode.SplitBeforeOffset(const aSplitOffset: Integer): TPatternTrieNode;
begin
  // Create a new node :
  Result := TPatternTrieNode.Create;
  // Split the Pattern in two, and put the right part in the new node :
  Result.Pattern := Copy(Self.Pattern, aSplitOffset, MaxInt);
  // Shorten the original Pattern with the same length :
  Self.Pattern := Copy(Self.Pattern, 0, aSplitOffset);
  // Move all children over to this new node :
  Swap(MyChildren, Result.MyChildren);
  // Make the new node a child of this node :
  MyChildren.Add(Result);
  // No sorting needed
  Assert(MyChildren.Count = 1);
end;

function TPatternTrieNode.AddChild(const aFunctionPattern: TPattern; const aPatternOffset: Integer): TPatternTrieNode;
begin
  // Create a new child for this function :
  Result := TPatternTrieNode.Create;
  // Determine the Pattern :
  Result.Pattern := Copy(aFunctionPattern, aPatternOffset, MaxInt);
  // Add this child to the list :
  MyChildren.Add(Result);
end;

function TPatternTrieNode.AddLeaf(const aFunction: PVersionedXboxLibraryFunction): Boolean;
var
  i: Integer;
  Leaf: TPatternTrieLeaf;
begin
  // Search in all leafs, to see if this function is already present :
  for i := 0 to NrChildren - 1 do
  begin
    Leaf := TPatternTrieLeaf(Children[i]);

    // Check if there's a leaf already with the same name, from the same library :
    if  (Leaf.VersionedXboxLibraryFunction.Name = aFunction.Name)
    and (Leaf.VersionedXboxLibraryFunction.VersionedXboxLibrary = aFunction.VersionedXboxLibrary) then
    begin
      // If so, don't add this duplicate (these do occur somehow).
      Result := False;
      Exit;
    end;
  end;

  // Create a new leaf for this function :
  Leaf := TPatternTrieLeaf.Create;
  // Register the Function :
  Leaf.VersionedXboxLibraryFunction := aFunction;
  // Add this leaf to the list :
  MyChildren.Add(Leaf);

  // Indicate that a leaf was added :
  Result := True;
end;

function TPatternTrieNode.AddPattern(const aFunction: PVersionedXboxLibraryFunction;
  const aFunctionPattern: TPattern; const aPatternOffset: Integer): TPatternTrieNode;
var
  MatchLen: Integer;
begin
  // Search for a match in the existing children first :
  Result := FindLongestMatchingChild(aFunctionPattern, aPatternOffset, {out}MatchLen);

  // Check if there should be a new child for this part :
  if Result = nil then
  begin
    // Not a single byte matches the trie, so create a new child node for this :
    Result := AddChild(aFunctionPattern, aPatternOffset);
    // Continue the remainder of this method with the indication that
    // the whole pattern is matched now :
    MatchLen := PATTERNSIZE;
  end;

  // If the pattern wasn't matched completely yet :
  if (aPatternOffset + MatchLen) < PATTERNSIZE then
  begin
    // Check if the matched pattern was only partially covered :
    if MatchLen < Length(Result.Pattern) then
      // If so, split this child in two :
      Result.SplitBeforeOffset(MatchLen);

    // And add the rest of this function to a new child :
    Result := Result.AddPattern(aFunction, aFunctionPattern, aPatternOffset + MatchLen);
  end
  else
    // Now that the complete pattern is present, add the leaf to this last node :
    if not Result.AddLeaf(aFunction) then
      // If that failed (because this is a duplicate), return a nil :
      Result := nil;
end;

// Based on Classes.BinToHex
function TPatternTrieNode.NodeAsString: string;
const
  NibbleHexChars: array[0..15] of Char = '0123456789ABCDEF';
var
  P: PChar;
  i: Integer;
begin
  SetLength(Result, (Length(Pattern) * 2) + 1);
  P := PChar(Result);
  for i := 0 to Length(Pattern) - 1 do
  begin
    if Pattern[i] < 256 then
    begin
      P[0] := NibbleHexChars[Byte(Pattern[i]) shr 4];
      P[1] := NibbleHexChars[Byte(Pattern[i]) and $F];
    end
    else
    begin
      P[0] := '.';
      P[1] := '.';
    end;

    Inc(P, 2);
  end;

  P[0] := ':';
end;

{ TPatternTrieLeaf }

function TPatternTrieLeaf.NodeAsString: string;
begin
  Result := Format('%d. %.2x %.4x %.4x [%8s %4d] %s', [
    LeafNr,
    VersionedXboxLibraryFunction.CRCLength,
    VersionedXboxLibraryFunction.CRCValue,
    VersionedXboxLibraryFunction.TotalLength,
    VersionedXboxLibraryFunction.VersionedXboxLibrary.LibName,
    VersionedXboxLibraryFunction.VersionedXboxLibrary.LibVersion,
    VersionedXboxLibraryFunction.Name
    ]);
end;

{ TPatternTrie }

function TPatternTrie.NodeAsString: string;
begin
  Result := 'Trie dump:';
end;

procedure TPatternTrie.Sort;

  procedure _SortNode(aPatternNode: TPatternTrieNode);
  var
    i: Integer;
    ChildrenAreLeafNodes: Boolean;
  begin
    // Skip nodes that have no children :
    if aPatternNode.NrChildren = 0 then
      Exit;

    // Determine if the children are leafs or nodes :
    ChildrenAreLeafNodes := (aPatternNode.Children[0].ClassType = TPatternTrieLeaf);

    // Leafs need other sorting than nodes :
    if ChildrenAreLeafNodes then
      aPatternNode.MyChildren.Sort(@PatternTrie_LeafCompare)
    else
      aPatternNode.MyChildren.Sort(@PatternTrie_NodeCompare);

    // Now loop over these (sorted) children :
    for i := 0 to aPatternNode.NrChildren - 1 do
    begin
      if ChildrenAreLeafNodes then
        // Leafs need an incremental number :
        TPatternTrieLeaf(aPatternNode.Children[i]).LeafNr := i
      else
        // And nodes need to be sorted too (this works recursively) :
        _SortNode(aPatternNode.Children[i]);
    end;
  end;

begin
  // Sort the whole trie :
  _SortNode(Self);
end;

procedure TPatternTrie.Dump(const aOutput: TStrings);
var
  IndentStr: TStringList;

  procedure _DumpNode(aPatternNode: TPatternTrieNode; const aIndentLevel: Integer);
  var
    i: Integer;
  begin
    // Output an indented string (produced by the node/leaf itself) :
    aOutput.Add(IndentStr[aIndentLevel] + aPatternNode.NodeAsString);

    // Also dump the children (if there are any), but then one indent-level further :
    for i := 0 to aPatternNode.NrChildren - 1 do
      _DumpNode(aPatternNode.Children[i], aIndentLevel + 1);
  end;

begin
  IndentStr := TStringList.Create;
  try
    // Prepare the indent strings, so we don't have to call StringOfChar thousands of times :
    while IndentStr.Count < PATTERNSIZE do
      IndentStr.Add(StringOfChar(' ', (IndentStr.Count * 2)));
    IndentStr.Insert(0, '');

    // Now dump the whole trie :
    _DumpNode(Self, 0);
  finally
    FreeAndNil(IndentStr);
  end;
end;

procedure TPatternTrie.Save(const aFileName: string);
var
  UniqueStrings: TStringList;
  GlobalFunctions: TStringList;
  OutputFile: TFileStream;

  procedure _WriteLeaf(const aLeaf: TPatternTrieLeaf);
  var
    StoredLibraryFunction: RStoredLibraryFunction;
  begin
    StoredLibraryFunction.GlobalFunctionIndex := GlobalFunctions.IndexOf(aLeaf.VersionedXboxLibraryFunction.Name);
    StoredLibraryFunction.LibraryIndex := VersionedLibraries.IndexOf(aLeaf.VersionedXboxLibraryFunction.VersionedXboxLibrary);
    StoredLibraryFunction.CRCLength := aLeaf.VersionedXboxLibraryFunction.CRCLength;
    StoredLibraryFunction.CRCValue := aLeaf.VersionedXboxLibraryFunction.CRCValue;
    StoredLibraryFunction.FunctionLength := aLeaf.VersionedXboxLibraryFunction.TotalLength;
    OutputFile.WriteBuffer(StoredLibraryFunction, SizeOf(RStoredLibraryFunction));
  end;

  procedure _WriteTrieNodes(const aPatternNode: TPatternTrieNode; Depth: Integer);
  var
    i: Integer;
    ChildrenAreLeafNodes: Boolean;
    Len, NrFixed, NrWildcards, PrevIndex: Integer;
    StoredTrieNode: RStoredTrieNode;
    PreviousSiblingOffset: TByteOffset;

    procedure _SetPreviousSibling_NextSiblingOffset(var aPreviousSiblingPosition: TByteOffset);
    var
      CurrentPosition: TByteOffset;
    begin
      // Remember this position (this is where the next sibling will be written) :
      CurrentPosition := OutputFile.Position;
      // Go the the 'NextSiblingOffset' member of the previous sibling :
      OutputFile.Position := aPreviousSiblingPosition;
      OutputFile.Write(CurrentPosition, SizeOf(TByteOffset));
      // Return to the previous position, and remember that for the next call to this method :
      OutputFile.Position := CurrentPosition;
      {var}aPreviousSiblingPosition := CurrentPosition;
    end;

    procedure _FlushStretch(Index: Integer);
    var
      b: Byte;
      i: Integer;
    begin
      b := (NrFixed shl 3);
      case NrWildcards of
        0: if NrFixed = PATTERNSIZE then
             b := NODE_ALLFIXED; // 32 can't be measured, but use a special flag for that
        4: b := b or NODE_5BITFIXED_4WILDCARDS;
        8: b := b or NODE_5BITFIXED_8WILDCARDS;
      else
        if Depth = PATTERNSIZE then
          b := b or NODE_5BITFIXED_ALLWILDCARDS
        else
          raise Exception.Create('unhandled case!');
      end;

      // Determine it there's followup :
      if Index < Len then
        b := b or 4;

      // Write out the heading-byte of this stretch:
      OutputFile.Write(b, 1);

      // Write out the fixed bytes for this stretch :
      for i := PrevIndex to Index - 1 do
        if aPatternNode.Pattern[i] <> PatternDontCareValue then
        begin
          b := Byte(aPatternNode.Pattern[i]);
          OutputFile.Write(b, 1);
        end;

      // Now that we've flushed, initialize the next stretch :
      PrevIndex := Index;
      NrFixed := 0;
      NrWildcards := 0;
    end;

  begin
    // All other nodes have at least 1 byte of pattern data, but the root has no data.
    // We could prevent storage for root, but that would complicate the reading code.
    // So root is handled here like any other node - without any special cases.

    // Write the TrieNode :
    StoredTrieNode.NextSiblingOffset := 0;
    Len := SizeOf(RStoredTrieNode);
    if aPatternNode.NrChildren < 128 then
    begin
      // With a small number of children, store the node with 1 byte less :
      StoredTrieNode.NrChildrenByte1 := Byte(aPatternNode.NrChildren);
      Dec(Len, SizeOf(StoredTrieNode.NrChildrenByte2));
    end
    else
    begin
      // With many children, use both bytes :
      StoredTrieNode.NrChildrenByte1 := Byte(aPatternNode.NrChildren shr 8) or 128;
      StoredTrieNode.NrChildrenByte2 := Byte(aPatternNode.NrChildren);
    end;

    // Write the node record to file already (it will be updated later on) :
    OutputFile.WriteBuffer(StoredTrieNode, Len);

    // Determine how many pattern bytes need to be handled :
    Len := Length(aPatternNode.Pattern);

    // Correct the Depth already :
    Inc(Depth, Len);

    // Loop over the pattern, split it up in stretches and flush it along the way :
    NrFixed := 0;
    NrWildcards := 0;
    PrevIndex := 0;
    for i := 0 to Len - 1 do
    begin
      if aPatternNode.Pattern[i] = PatternDontCareValue then
        Inc(NrWildcards)
      else
      begin
        // Once we start a new stretch of fixed bytes, flush the previous stretch :
        if (NrWildcards > 0) then
          _FlushStretch(i);

        Inc(NrFixed);
      end;
    end;

    // Flush the last stretch :
    _FlushStretch(Len);

    // Remember that the first sibling of all children starts here :
    PreviousSiblingOffset := OutputFile.Position;

    // Determine if the children are leafs or nodes :
    ChildrenAreLeafNodes := (aPatternNode.Children[0].ClassType = TPatternTrieLeaf);
    for i := 0 to aPatternNode.NrChildren - 1 do
    begin
      // Write the children (either leafs or recursive nodes) :
      if ChildrenAreLeafNodes then
        _WriteLeaf(TPatternTrieLeaf(aPatternNode.Children[i]))
      else
      begin
        // Update the previous sibling's NextSiblingOffset member :
        if {HasPrevious=}i > 0 then
          _SetPreviousSibling_NextSiblingOffset({var}PreviousSiblingOffset);

        _WriteTrieNodes(aPatternNode.Children[i], Depth);
      end;
    end;
  end;

var
  i: Integer;
  StringOffsets: array of TByteOffset;
  StoredSignatureTrieHeader: RStoredSignatureTrieHeader;
  StoredLibrary: RStoredLibrary;
  StoredGlobalFunction: RStoredGlobalFunction;
begin
  OutputFile := TFileStream.Create(aFileName, fmCreate);
  UniqueStrings := TStringList.Create;
  GlobalFunctions := TStringList.Create;
  try
    // Collect all global function names in a string list :
    GlobalFunctions.Sorted := True;
    GlobalFunctions.Duplicates := dupIgnore;
    GlobalFunctions.CaseSensitive := False;
    for i := 0 to VersionedFunctions.Count - 1 do
      GlobalFunctions.Add(PVersionedXboxLibraryFunction(VersionedFunctions[i]).Name);

    // Collect all strings, and bring it down to one occurrence per unique string :
    UniqueStrings.Assign(GlobalFunctions);
    // There's no TStringList.Assign, so do that ourselves here :
    UniqueStrings.Sorted := True;
    UniqueStrings.Duplicates := dupIgnore;
    UniqueStrings.CaseSensitive := False;
    // Also, add all library names to the unique string list :
    for i := 0 to VersionedLibraries.Count - 1 do
      UniqueStrings.Add(PVersionedXboxLibrary(VersionedLibraries[i]).LibName);

    // Initialize the header record :
    ZeroMemory(@StoredSignatureTrieHeader, SizeOf(StoredSignatureTrieHeader));
    StoredSignatureTrieHeader.Header := 'DxTrie';

    // Initialize the string table information :
    StoredSignatureTrieHeader.StringTable.NrStrings := UniqueStrings.Count;
    StoredSignatureTrieHeader.StringTable.StringOffsets := SizeOf(StoredSignatureTrieHeader);
    StoredSignatureTrieHeader.StringTable.AnsiCharData := StoredSignatureTrieHeader.StringTable.StringOffsets + TByteOffset(SizeOf(TByteOffset) * UniqueStrings.Count);

    // Start by writing the AnsiCharData :
    OutputFile.Position := StoredSignatureTrieHeader.StringTable.AnsiCharData;
    SetLength(StringOffsets, UniqueStrings.Count);
    for i := 0 to UniqueStrings.Count - 1 do
    begin
      OutputFile.WriteBuffer(UniqueStrings[i][1], Length(UniqueStrings[i]));
      StringOffsets[i] := OutputFile.Position;
    end;

    // Remember this location, so we know where to put the LibraryTable :
    StoredSignatureTrieHeader.LibraryTable.NrOfLibraries := VersionedLibraries.Count;
    StoredSignatureTrieHeader.LibraryTable.LibrariesOffset := OutputFile.Position;

    // Now that the string data is written, put the StringOffsets in place :
    OutputFile.Position := StoredSignatureTrieHeader.StringTable.StringOffsets;
    OutputFile.WriteBuffer(StringOffsets[0], Length(StringOffsets) * SizeOf(StringOffsets[0]));
    SetLength(StringOffsets, 0);

    // Write libraries :
    OutputFile.Position := StoredSignatureTrieHeader.LibraryTable.LibrariesOffset;
    for i := 0 to VersionedLibraries.Count - 1 do
    begin
      StoredLibrary.LibVersion := PVersionedXboxLibrary(VersionedLibraries[i]).LibVersion;
      StoredLibrary.LibNameIndex := UniqueStrings.IndexOf(PVersionedXboxLibrary(VersionedLibraries[i]).LibName);

      OutputFile.WriteBuffer(StoredLibrary, SizeOf(StoredLibrary));
    end;

    // Write global functions :
    StoredSignatureTrieHeader.GlobalFunctionTable.NrOfFunctions := GlobalFunctions.Count;
    StoredSignatureTrieHeader.GlobalFunctionTable.GlobalFunctionsOffset := OutputFile.Position;

    for i := 0 to GlobalFunctions.Count - 1 do
    begin
      StoredGlobalFunction.FunctionNameIndex := UniqueStrings.IndexOf(GlobalFunctions[i]);
      OutputFile.WriteBuffer(StoredGlobalFunction, SizeOf(StoredGlobalFunction));
    end;

    // Write trie :
    StoredSignatureTrieHeader.TrieRootNode := OutputFile.Position;

    // Write out a compact format for all nodes and leafs.
    // This whole file will be included in our Xbox Krnl DLL as a resource,
    // so it's going to be a readonly structure, that must be fast to parse :
    _WriteTrieNodes(Self, 0);

    // Last, go back to the start of the file, and write the completed header there :
    OutputFile.Position := 0;
    OutputFile.WriteBuffer(StoredSignatureTrieHeader, SizeOf(StoredSignatureTrieHeader));
  finally
    FreeAndNil(GlobalFunctions);
    FreeAndNil(UniqueStrings);
    FreeAndNil(OutputFile);
  end;
end;

//

type
  PPatternScanningContext = ^RPatternScanningContext;
  RPatternScanningContext = record
    PatternTrie: TPatternTrie;
    OnlyPatches: Boolean;
    VersionedXboxLibrary: PVersionedXboxLibrary;
  end;

function ParseAndAppendPatternLineToTrie_Callback(aLine: PChar; aLength: Integer; aContext: PPatternScanningContext): Boolean;
const
  PATTERN_START_OF_NAME = 85;
  PATTERN_VALID_NAME_CHARACTERS = ['_', 'a'..'z', 'A'..'Z', '0'..'9', '@', ':', '?', '$'];
var
  VersionedXboxLibraryFunction: PVersionedXboxLibraryFunction;
  VersionedXboxLibraryFunctionPattern: TPattern;
  i, Value: Integer;
  aStart: PChar;
begin
  // Stop at a '-' marker :
  Result := (aLine^ <> '-');
  if not Result then
    Exit;

  // Lines must at least be 86 characters long :
  if aLength < PATTERN_START_OF_NAME + 1 then
    Exit;

  // Prepare the record which will contain this pattern's data :
  VersionedXboxLibraryFunction := AllocMem(SizeOf(RVersionedXboxLibraryFunction));
  VersionedXboxLibraryFunction.VersionedXboxLibrary := aContext.VersionedXboxLibrary;
  SetLength(VersionedXboxLibraryFunctionPattern, PATTERNSIZE);

  // Now, convert the first 32 bytes into a pattern :
  for i := 0 to PATTERNSIZE - 1 do
  begin
    if ScanHexByte({var}aLine, {var}Value) then
      // Every succesfully scanned hexadecimal byte, is added as-is to the patter-array :
      VersionedXboxLibraryFunctionPattern[i] := Value
    else
    begin
      // Everything else is probably a "don't care" indicator, so put that in here :
      VersionedXboxLibraryFunctionPattern[i] := PatternDontCareValue;
      Inc(aLine, 2);
    end;
  end;

  Assert(aLine^ = ' ');
  Inc(aLine);

  // Scan the CRC length :
  if ScanHexByte(aLine, Value) then
    VersionedXboxLibraryFunction.CRCLength := Byte(Value);
  Assert(aLine^ = ' ');
  Inc(aLine);

  // Scan the CRC value :
  if ScanHexWord(aLine, Value) then
    VersionedXboxLibraryFunction.CRCValue := Word(Value);
  Assert(aLine^ = ' ');
  Inc(aLine);

  // Scan the function length :
  if ScanHexWord(aLine, Value) then
    VersionedXboxLibraryFunction.TotalLength := Word(Value);
  Assert(aLine^ = ' ');
  Inc(aLine);

  // Scan (and skip) the function offset :
  Assert(aLine^ = ':');
  Inc(aLine);
  if ScanHexWord(aLine, Value) then
    ; // Ignore offset
  if aLine^ = '@' then
    Inc(aLine);
  Assert(aLine^ = ' ');
  Inc(aLine);

  // Scan the function name :
  aStart := aLine;
  repeat
    Inc(aLine);
  until not (aLine^ in PATTERN_VALID_NAME_CHARACTERS);

  // Remember the function name :
  SetString(VersionedXboxLibraryFunction.Name, aStart, aLine - aStart);

  // Now, see if we need to filter
  if aContext.OnlyPatches then
  begin
    // In this mode, skip all functions that aren't patched :
    if not IsXboxLibraryPatch(VersionedXboxLibraryFunction.Name) then
    begin
      // No leaf added, free the function :
      FreeMem(VersionedXboxLibraryFunction);
      Exit;
    end;
  end;

  // TODO : Here, we could scan cross-references and the trailing pattern,
  // but we ignore it for now; We'll visit this again when the first 32
  // pattern bytes + CRC aren't enough to detect important functions...

  // Now that the pattern line is scanned, add it to the trie :
  if aContext.PatternTrie.AddPattern(VersionedXboxLibraryFunction, VersionedXboxLibraryFunctionPattern, 0) = nil then
    // No leaf added, free the function :
    FreeMem(VersionedXboxLibraryFunction)
  else
    // The function was added to the trie, remember it :
    aContext.PatternTrie.VersionedFunctions.Add(VersionedXboxLibraryFunction);
end;

procedure ParseAndAppendPatternsToTrie(const aPatterns: PChar;
  const aPatternTrie: TPatternTrie;
  const aOnlyPatches: Boolean;
  const aLibrary: PVersionedXboxLibrary);
var
  PatternScanningContext: RPatternScanningContext;
begin
  // Set up the context for the line-parsing routine :
  PatternScanningContext.PatternTrie := aPatternTrie;
  PatternScanningContext.OnlyPatches := aOnlyPatches;
  PatternScanningContext.VersionedXboxLibrary := aLibrary;
  // Scan all pattern lines :
  ScanPCharLines(aPatterns, @ParseAndAppendPatternLineToTrie_Callback, @PatternScanningContext);
end;

function GeneratePatternTrie(const aPatternFiles: TStrings; const aOnlyPatches: Boolean): Integer;

  procedure _ProcessPatternFiles(aPatternTrie: TPatternTrie);
  var
    Input: TMemoryStream;
    i: Integer;
    PatternFilePath, LibName: string;
    VersionedXboxLibrary: PVersionedXboxLibrary;
  begin
    Input := TMemoryStream.Create;
    try
      for i := 0 to aPatternFiles.Count - 1 do
      begin
        // Get the Pattern FilePath, and figure out for which library and version it is :
        PatternFilePath := aPatternFiles[i];
        LibName := ChangeFileExt(ExtractFileName(PatternFilePath), '');

        // Create and initialize this new library :
        VersionedXboxLibrary := AllocMem(SizeOf(RVersionedXboxLibrary));
        VersionedXboxLibrary.LibVersion := StrToInt(Copy(LibName, 1, 4));
        Delete(LibName, 1, 4);
        VersionedXboxLibrary.LibName := LibName;
        aPatternTrie.VersionedLibraries.Add(VersionedXboxLibrary);

        // Load pattern file into memory:
        Input.LoadFromFile(PatternFilePath);

        // Parse patterns in this file and append them to the trie :
        ParseAndAppendPatternsToTrie(Input.Memory, aPatternTrie, aOnlyPatches, VersionedXboxLibrary);
      end;
    finally
      FreeAndNil(Input);
    end;
  end;

var
  PatternTrie: TPatternTrie;
  Output: TStringList;
  i: Integer;
begin
//  Result := -1;

  PatternTrie := TPatternTrie.Create;
  PatternTrie.VersionedLibraries := TList.Create;
  PatternTrie.VersionedFunctions := TList.Create;
  try
    WriteLn('Adding ' + IntToStr(aPatternFiles.Count) + ' pattern files to trie...');
    _ProcessPatternFiles(PatternTrie);

    WriteLn('Sorting the trie...');
    PatternTrie.Sort;

    WriteLn('Trie contains ' + IntToStr(PatternTrie.VersionedFunctions.Count) + ' unique patterns.');

    if DumpFileName <> '' then
    begin
      WriteLn('Dumping the trie to "' + DumpFileName + '"...');
      Output := TStringList.Create;
      try
        PatternTrie.Dump(Output);
        Output.SaveToFile(DumpFileName);
      finally
        FreeAndNil(Output);
      end;
    end;

    WriteLn('Saving the trie to "' + StoredTrieFileName + '"...');
    PatternTrie.Save(StoredTrieFileName);

    Result := ERROR_SUCCESS;
  finally
    for i := 0 to PatternTrie.VersionedFunctions.Count - 1 do
      FreeMem(PatternTrie.VersionedFunctions[i]);
    FreeAndNil(PatternTrie.VersionedFunctions);

    for i := 0 to PatternTrie.VersionedLibraries.Count - 1 do
      FreeMem(PatternTrie.VersionedLibraries[i]);
    FreeAndNil(PatternTrie.VersionedLibraries);
    FreeAndNil(PatternTrie);
  end;
end;

procedure PatternToTrie_Main;
var
  PatternFolder: string;
  PatternFiles: TStringList;
begin
  WriteLn(ChangeFileExt(ExtractFileName(ParamStr(0)), '') + ' - Converts Xbox pattern files to a trie file.'); // (and an Object Pascal unit).');
  WriteLn('This tool is part of the Dxbx Xbox emulator project.');
  WriteLn('See http://sourceforge.net/projects/dxbx');
  WriteLn('');

  if ParamCount < 1 then
  begin
    WriteLn('ERROR! Missing argument. Please supply a folder containing the Xbox *.pat files.');
    Exit;
  end;

  PatternFolder := ParamStr(1);
  PatternFiles := TStringList.Create;
  try
    if FindFiles(PatternFolder, {aFileMask=}'*.pat', PatternFiles) <= 0 then
    begin
      WriteLn('ERROR! No ".pat" pattern files found!');
      Exit;
    end;

    ExitCode := GeneratePatternTrie(PatternFiles, {aOnlyPatches=}False);
    if ExitCode = ERROR_SUCCESS then
      WriteLn('Done.')
    else
      WriteLn('ERROR! No trie file generated!');

  finally
    FreeAndNil(PatternFiles);
  end;
end;

end.
