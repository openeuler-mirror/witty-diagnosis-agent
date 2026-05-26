#!/usr/bin/env bun
interface PlatformTarget {
    dir: string;
    target: string;
    binary: string;
    description: string;
    pkgName: string;
}
export declare const PLATFORMS: PlatformTarget[];
export {};
