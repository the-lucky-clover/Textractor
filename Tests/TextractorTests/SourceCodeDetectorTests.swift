//
//  SourceCodeDetectorTests.swift
//  TextractorTests
//
//  Unit tests for SourceCodeDetector
//

import XCTest
@testable import Textractor

final class SourceCodeDetectorTests: XCTestCase {
    
    // MARK: - Swift Code Detection
    
    func testDetectsSwiftCode() {
        let swiftCode = """
        import Foundation
        
        struct User {
            let name: String
            let age: Int
        }
        
        func greet(_ user: User) -> String {
            return "Hello, \\(user.name)!"
        }
        """
        let result = SourceCodeDetector.analyze(swiftCode)
        XCTAssertTrue(result.isCode)
        XCTAssertEqual(result.language, "swift")
    }
    
    func testDetectsSwiftWithGenerics() {
        let swiftCode = """
        func map<T, U>(_ array: [T], _ transform: (T) -> U) -> [U] {
            return array.map(transform)
        }
        """
        let result = SourceCodeDetector.analyze(swiftCode)
        XCTAssertTrue(result.isCode)
        XCTAssertEqual(result.language, "swift")
    }
    
    // MARK: - Python Code Detection
    
    func testDetectsPythonCode() {
        let pythonCode = """
        import os
        import json
        
        def process_data(data: dict) -> list:
            results = []
            for item in data.get("items", []):
                if item.get("active"):
                    results.append(item["id"])
            return results
        
        class DataProcessor:
            def __init__(self, config: dict):
                self.config = config
        """
        let result = SourceCodeDetector.analyze(pythonCode)
        XCTAssertTrue(result.isCode)
        XCTAssertEqual(result.language, "python")
    }
    
    // MARK: - JavaScript/TypeScript Detection
    
    func testDetectsJavaScriptCode() {
        let jsCode = """
        import React from 'react';
        
        interface Props {
            name: string;
            age: number;
        }
        
        const UserCard: React.FC<Props> = ({ name, age }) => {
            return (
                <div className="user-card">
                    <h2>{name}</h2>
                    <p>Age: {age}</p>
                </div>
            );
        };
        
        export default UserCard;
        """
        let result = SourceCodeDetector.analyze(jsCode)
        XCTAssertTrue(result.isCode)
        XCTAssertTrue(result.language == "typescript" || result.language == "javascript")
    }
    
    // MARK: - C/C++ Detection
    
    func testDetectsCCode() {
        let cCode = """
        #include <stdio.h>
        #include <stdlib.h>
        
        struct Node {
            int data;
            struct Node* next;
        };
        
        void insert(struct Node** head, int data) {
            struct Node* newNode = (struct Node*)malloc(sizeof(struct Node));
            newNode->data = data;
            newNode->next = *head;
            *head = newNode;
        }
        """
        let result = SourceCodeDetector.analyze(cCode)
        XCTAssertTrue(result.isCode)
        XCTAssertEqual(result.language, "c")
    }
    
    // MARK: - Go Detection
    
    func testDetectsGoCode() {
        let goCode = """
        package main
        
        import (
            "fmt"
            "encoding/json"
        )
        
        type User struct {
            Name string `json:"name"`
            Age  int    `json:"age"`
        }
        
        func main() {
            user := User{Name: "Alice", Age: 30}
            data, _ := json.Marshal(user)
            fmt.Println(string(data))
        }
        """
        let result = SourceCodeDetector.analyze(goCode)
        XCTAssertTrue(result.isCode)
        XCTAssertEqual(result.language, "go")
    }
    
    // MARK: - Rust Detection
    
    func testDetectsRustCode() {
        let rustCode = """
        use std::collections::HashMap;
        
        struct User {
            name: String,
            age: u32,
        }
        
        fn process_users(users: Vec<User>) -> HashMap<String, u32> {
            let mut map = HashMap::new();
            for user in users {
                map.insert(user.name, user.age);
            }
            map
        }
        """
        let result = SourceCodeDetector.analyze(rustCode)
        XCTAssertTrue(result.isCode)
        XCTAssertEqual(result.language, "rust")
    }
    
    // MARK: - Ruby Detection
    
    func testDetectsRubyCode() {
        let rubyCode = """
        class User
            attr_accessor :name, :age
            
            def initialize(name, age)
                @name = name
                @age = age
            end
            
            def greet
                puts "Hello, #{@name}!"
            end
        end
        
        user = User.new("Alice", 30)
        user.greet
        """
        let result = SourceCodeDetector.analyze(rubyCode)
        XCTAssertTrue(result.isCode)
        XCTAssertEqual(result.language, "ruby")
    }
    
    // MARK: - Bash Detection
    
    func testDetectsBashCode() {
        let bashCode = """
        #!/bin/bash
        
        set -euo pipefail
        
        process_files() {
            local dir="$1"
            for file in "$dir"/*.txt; do
                if [[ -f "$file" ]]; then
                    echo "Processing $file"
                fi
            done
        }
        
        main() {
            process_files "/tmp/data"
        }
        
        main "$@"
        """
        let result = SourceCodeDetector.analyze(bashCode)
        XCTAssertTrue(result.isCode)
        XCTAssertEqual(result.language, "bash")
    }
    
    // MARK: - Non-Code Detection
    
    func testRejectsPlainText() {
        let plainText = """
        Lorem ipsum dolor sit amet consectetur adipiscing elit.
        Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
        Ut enim ad minim veniam quis nostrud exercitation ullamco.
        """
        let result = SourceCodeDetector.analyze(plainText)
        XCTAssertFalse(result.isCode)
    }
    
    func testRejectsShortText() {
        let shortText = "Hello world"
        let result = SourceCodeDetector.analyze(shortText)
        XCTAssertFalse(result.isCode)
    }
    
    func testRejectsTwoLines() {
        let twoLines = "Line one\nLine two"
        let result = SourceCodeDetector.analyze(twoLines)
        XCTAssertFalse(result.isCode)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyString() {
        let result = SourceCodeDetector.analyze("")
        XCTAssertFalse(result.isCode)
    }
    
    func testWhitespaceOnly() {
        let result = SourceCodeDetector.analyze("   \n\t\n  ")
        XCTAssertFalse(result.isCode)
    }
    
    func testCodeWithMixedContent() {
        let mixed = """
        Here is some code:
        
        func hello() {
            print("Hello")
        }
        
        And here is more text.
        """
        let result = SourceCodeDetector.analyze(mixed)
        // Should detect as code since it has code patterns
        XCTAssertTrue(result.isCode)
    }
    
    // MARK: - Indentation Preservation
    
    func testPreserveIndentationTabs() {
        let codeWithTabs = "\tfunc test() {\n\t\tprint(\"hello\")\n\t}"
        let preserved = SourceCodeDetector.preserveIndentation(codeWithTabs)
        XCTAssertTrue(preserved.contains("    func test()"))
        XCTAssertTrue(preserved.contains("        print"))
    }
    
    func testPreserveIndentationSpaces() {
        let codeWithSpaces = "    func test() {\n        print(\"hello\")\n    }"
        let preserved = SourceCodeDetector.preserveIndentation(codeWithSpaces)
        XCTAssertEqual(preserved, codeWithSpaces)
    }
    
    func testTrimTrailingWhitespace() {
        let codeWithTrailing = "func test() {\n    print(\"hello\")   \n}"
        let preserved = SourceCodeDetector.preserveIndentation(codeWithTrailing)
        XCTAssertFalse(preserved.contains("hello\")   "))
    }
    
    // MARK: - Formatted Output
    
    func testFormattedOutputWrapsInFencedBlock() {
        let swiftCode = """
        func test() {
            print("hello")
        }
        """
        let result = SourceCodeDetector.analyze(swiftCode)
        let formatted = result.formatted
        // Should be wrapped in a fenced code block with some language
        XCTAssertTrue(formatted.hasPrefix("```"))
        XCTAssertTrue(formatted.hasSuffix("\n```"))
        XCTAssertTrue(result.isCode)
        XCTAssertNotNil(result.language)
    }
    
    func testNonCodeFormattedReturnsOriginal() {
        let plainText = "This is not code"
        let result = SourceCodeDetector.analyze(plainText)
        let formatted = result.formatted
        XCTAssertEqual(formatted, plainText)
    }
    
    // MARK: - JSON Detection
    
    func testDetectsJSON() {
        let jsonCode = """
        {
            "name": "Alice",
            "age": 30,
            "active": true,
            "tags": ["user", "admin"]
        }
        """
        let result = SourceCodeDetector.analyze(jsonCode)
        XCTAssertTrue(result.isCode)
        XCTAssertEqual(result.language, "json")
    }
    
    // MARK: - XML/HTML Detection
    
    func testDetectsXML() {
        let xmlCode = """
        <?xml version="1.0"?>
        <users>
            <user id="1">
                <name>Alice</name>
            </user>
        </users>
        """
        let result = SourceCodeDetector.analyze(xmlCode)
        XCTAssertTrue(result.isCode)
        XCTAssertTrue(result.language == "xml" || result.language == "html")
    }
}