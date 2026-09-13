#!/usr/bin/env python3
"""
GitHub Actions Workflow Analyzer

Analyzes workflow YAML files for common issues, anti-patterns, and optimization opportunities.
Usage: python analyze_workflow.py <workflow_file.yml>
"""

import yaml
import sys
from pathlib import Path
from typing import Dict, List, Any


class WorkflowAnalyzer:
    """Analyze GitHub Actions workflows for best practices."""
    
    def __init__(self, workflow_path: str):
        self.path = Path(workflow_path)
        self.workflow = None
        self.issues = []
        self.warnings = []
        self.suggestions = []
        
    def load_workflow(self) -> bool:
        """Load and parse the workflow YAML file."""
        try:
            with open(self.path, 'r') as f:
                self.workflow = yaml.safe_load(f)
            return True
        except Exception as e:
            self.issues.append(f"Failed to parse YAML: {e}")
            return False
    
    def check_permissions(self):
        """Check for explicit permission definitions."""
        if 'permissions' not in self.workflow:
            self.warnings.append(
                "No permissions block found. Consider adding explicit permissions "
                "for security (contents, packages, id-token, etc.)"
            )
        else:
            perms = self.workflow['permissions']
            if perms == 'write-all':
                self.suggestions.append(
                    "Avoid 'write-all' permission. Use specific scopes for better security."
                )
    
    def check_timeouts(self):
        """Check for timeout configurations on jobs."""
        jobs = self.workflow.get('jobs', {})
        
        if not jobs:
            self.warnings.append("No jobs found in workflow")
            return
            
        for job_id, job_config in jobs.items():
            if 'timeout-minutes' not in job_config:
                self.suggestions.append(
                    f"Job '{job_id}' has no timeout-minutes set. "
                    "Consider adding one to prevent hung jobs."
                )
    
    def check_caching(self):
        """Check for caching strategies."""
        jobs = self.workflow.get('jobs', {})
        
        uses_cache = False
        for job_config in jobs.values():
            steps = job_config.get('steps', [])
            for step in steps:
                if isinstance(step, dict) and 'uses' in step:
                    action = step['uses']
                    if 'cache@v4' in action or 'cache@v3' in action:
                        uses_cache = True
                        # Check cache key quality
                        with_config = step.get('with', {})
                        key = with_config.get('key', '')
                        if not key:
                            self.warnings.append(
                                f"Cache step found without explicit key. "
                                "Define a proper cache key to avoid collisions."
                            )
                        elif 'hashFiles' not in key:
                            self.suggestions.append(
                                "Consider adding hashFiles() to cache keys for better invalidation."
                            )
        
        if jobs and not uses_cache:
            self.suggestions.append(
                "No caching found. Consider adding dependency caching to reduce build times."
            )
    
    def check_matrix_strategy(self):
        """Check matrix strategy configuration."""
        jobs = self.workflow.get('jobs', {})
        
        for job_id, job_config in jobs.items():
            strategy = job_config.get('strategy', {})
            if 'matrix' in strategy:
                # Check fail-fast setting
                if strategy.get('fail-fast', True):
                    self.suggestions.append(
                        f"Job '{job_id}' has fail-fast=true. "
                        "Consider false to see all test results."
                    )
    
    def check_action_versions(self):
        """Check for pinned action versions."""
        jobs = self.workflow.get('jobs', {})
        
        for job_config in jobs.values():
            steps = job_config.get('steps', [])
            for step in steps:
                if isinstance(step, dict) and 'uses' in step:
                    action = step['uses']
                    
                    # Check for unpinned versions (using @main or @master)
                    if '@main' in action or '@master' in action:
                        self.warnings.append(
                            f"Action '{action}' uses branch reference. "
                            "Consider pinning to a specific version."
                        )
                    
                    # Check for common outdated versions
                    if any(act in action for act in ['checkout@v3', 'setup-node@v3']):
                        self.suggestions.append(
                            f"Action '{action}' may have newer versions available."
                        )
    
    def check_triggers(self):
        """Check workflow trigger configuration."""
        triggers = self.workflow.get('on', {})
        
        if isinstance(triggers, str):
            # Simple trigger like "on: push"
            return
            
        if 'push' in triggers:
            push_config = triggers['push']
            if isinstance(push_config, dict) and 'paths-ignore' not in push_config:
                self.suggestions.append(
                    "Consider adding paths-ignore for docs/ changes to reduce CI cost."
                )
        
        # Check for workflow_dispatch (manual trigger)
        if 'workflow_dispatch' not in triggers:
            self.suggestions.append(
                "Consider adding workflow_dispatch for manual triggering capability."
            )

    def check_artifacts(self):
        """Check artifact upload/download patterns."""
        jobs = self.workflow.get('jobs', {})
        
        uploads = []
        downloads = []
        
        for job_id, job_config in jobs.items():
            steps = job_config.get('steps', [])
            for step in steps:
                if isinstance(step, dict) and 'uses' in step:
                    action = step['uses']
                    if 'upload-artifact' in action:
                        uploads.append(job_id)
                    if 'download-artifact' in action:
                        downloads.append(job_id)
        
        # Check for missing artifact names
        for job_config in jobs.values():
            steps = job_config.get('steps', [])
            for step in steps:
                if isinstance(step, dict) and 'uses' in step:
                    if 'upload-artifact' in step['uses']:
                        with_config = step.get('with', {})
                        if not with_config.get('retention-days'):
                            self.suggestions.append(
                                "Artifact upload found without retention-days. "
                                "Set a reasonable retention period to save storage."
                            )

    def check_secrets_usage(self):
        """Check for proper secrets usage patterns."""
        import re
        
        workflow_str = yaml.dump(self.workflow)
        
        # Check for direct secret access in matrix context
        if 'strategy' in str(self.workflow) and 'secrets[' not in workflow_str:
            # Complex check would be needed here
            pass
    
    def generate_report(self):
        """Generate analysis report."""
        print(f"\n{'='*60}")
        print(f"Workflow Analysis Report: {self.path}")
        print('='*60)
        
        if self.issues:
            print(f"\n❌ Issues ({len(self.issues)}):")
            for issue in self.issues:
                print(f"   • {issue}")
        
        if self.warnings:
            print(f"\n⚠️  Warnings ({len(self.warnings)}):")
            for warning in self.warnings:
                print(f"   • {warning}")
                
        if self.suggestions:
            print(f"\n💡 Suggestions ({len(self.suggestions)}):")
            for suggestion in self.suggestions:
                print(f"   • {suggestion}")
        
        if not self.issues and not self.warnings and not self.suggestions:
            print("\n✅ No major issues found!")
            
        print('='*60 + '\n')

    def analyze(self):
        """Run all checks."""
        if not self.load_workflow():
            return
            
        self.check_permissions()
        self.check_timeouts()
        self.check_caching()
        self.check_matrix_strategy()
        self.check_action_versions()
        self.check_triggers()
        self.check_artifacts()


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        print("Usage: python analyze_workflow.py <workflow_file.yml>")
        sys.exit(1)
    
    workflow_path = sys.argv[1]
    
    if not Path(workflow_path).exists():
        print(f"Error: File '{workflow_path}' not found")
        sys.exit(1)
    
    analyzer = WorkflowAnalyzer(workflow_path)
    analyzer.analyze()
    analyzer.generate_report()


if __name__ == '__main__':
    main()