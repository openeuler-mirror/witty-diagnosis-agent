#!/usr/bin/env python3
# =============================================================================
# 脚本：output_manager.py
# 用途：统一管理 flamegraph-analysis 的输出目录和文件路径
# 功能：
#   - get_output_dir()      : 获取输出目录，不存在则创建
#   - ensure_output_dir()   : 确保输出目录存在
#   - get_output_path()     : 获取输出文件的完整路径
#   - OutputContext         : 输出上下文管理器
#   - parse_args_with_output_dir() : 为 argparse 添加 --output-dir 参数
# 说明：默认输出目录为 /tmp/flamegraph-analysis_TIMESTAMP_UUID
# =============================================================================

import os
import sys
import uuid
from pathlib import Path
from datetime import datetime

OUTPUT_BASE = '/tmp'
SKILL_NAME = 'flamegraph-analysis'


def get_output_dir(create: bool = True) -> str:
    """获取输出目录，不存在则创建"""
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    unique_id = uuid.uuid4().hex[:6]
    dir_name = f'{SKILL_NAME}_{timestamp}_{unique_id}'
    output_dir = os.path.join(OUTPUT_BASE, dir_name)

    if create and not os.path.exists(output_dir):
        os.makedirs(output_dir, exist_ok=True)

    return output_dir


def ensure_output_dir(output_dir: str) -> str:
    """确保输出目录存在"""
    if not os.path.exists(output_dir):
        os.makedirs(output_dir, exist_ok=True)
    return output_dir


def get_output_path(output_dir: str, filename: str) -> str:
    """获取输出文件的完整路径"""
    return os.path.join(output_dir, filename)


def init_output_dir(timestamp: str = None) -> str:
    """初始化带时间戳的输出目录（用于 SKILL.md 中的命令预生成）"""
    if timestamp is None:
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    unique_id = uuid.uuid4().hex[:6]
    dir_name = f'{SKILL_NAME}_{timestamp}_{unique_id}'
    output_dir = os.path.join(OUTPUT_BASE, dir_name)
    return output_dir, dir_name


class OutputContext:
    """输出上下文管理器"""

    def __init__(self, output_dir: str = None):
        if output_dir is None:
            self.output_dir = get_output_dir(create=True)
        else:
            self.output_dir = ensure_output_dir(output_dir)
        self.files = {}

    def register(self, key: str, filename: str) -> str:
        """注册一个输出文件"""
        path = get_output_path(self.output_dir, filename)
        self.files[key] = path
        return path

    def get_path(self, key: str) -> str:
        """获取已注册文件的路径"""
        return self.files.get(key)

    def get_dir(self) -> str:
        """获取输出目录"""
        return self.output_dir

    def list_files(self) -> dict:
        """列出所有生成的文件"""
        return self.files.copy()


def parse_args_with_output_dir(parser):
    """为 argparse 添加 --output-dir 参数"""
    parser.add_argument('--output-dir', '-d',
                       help='Output directory (default: /tmp/flamegraph-analysis_TIMESTAMP)',
                       default=None)
    return parser


def get_default_output_dir() -> str:
    """获取默认输出目录（仅返回路径，不创建）"""
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    unique_id = uuid.uuid4().hex[:6]
    dir_name = f'{SKILL_NAME}_{timestamp}_{unique_id}'
    return os.path.join(OUTPUT_BASE, dir_name)


if __name__ == '__main__':
    print(f'Output base: {OUTPUT_BASE}')
    print(f'Default output dir: {get_default_output_dir()}')
    print(f'Created output dir: {get_output_dir()}')