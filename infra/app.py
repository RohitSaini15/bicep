# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

import os
from aws_cdk import App, Environment
from stacks.cicd_stack import CICDPipelineStack
from stacks.application_stack import ApplicationStack
import cdklabs.aws_data_solutions_framework as dsf

app = App()

default_environment = Environment(
    # Configure your environment as needed, see https://docs.aws.amazon.com/cdk/v2/guide/environments.html
    region=os.environ["CDK_DEFAULT_REGION"], 
    account=os.environ["CDK_DEFAULT_ACCOUNT"]     
)

# Create a CICD Pipeline Stack that will provision an Application stack and a CICD for it
pipeline_stack = CICDPipelineStack(
    app, "CICDPipeline", env=default_environment
)

# Deploy core Application stack without CICD stack
application_stack = ApplicationStack(
    app, "ApplicationStack", env=default_environment
)

app.synth()
