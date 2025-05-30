// Copyright The HTNN Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package cors

import (
	"fmt"

	cors "github.com/envoyproxy/go-control-plane/envoy/extensions/filters/http/cors/v3"

	"mosn.io/htnn/api/pkg/filtermanager/api"
	"mosn.io/htnn/api/pkg/plugins"
)

const (
	Name = "cors"
)

func init() {
	plugins.RegisterPluginType(Name, &Plugin{})
}

type Plugin struct {
	plugins.PluginMethodDefaultImpl
}

func (p *Plugin) Type() plugins.PluginType {
	return plugins.TypeSecurity
}

func (p *Plugin) Order() plugins.PluginOrder {
	return plugins.PluginOrder{
		Position:  plugins.OrderPositionOuter,
		Operation: plugins.OrderOperationInsertLast,
	}
}

type CustomConfig struct {
	cors.CorsPolicy
}

func (conf *CustomConfig) Validate() error {
	err := conf.CorsPolicy.Validate()
	if err != nil {
		return err
	}

	if len(conf.CorsPolicy.GetAllowOriginStringMatch()) == 0 {
		return fmt.Errorf("cors allowOriginStringMatch is required")
	}

	if len(conf.CorsPolicy.GetAllowMethods()) == 0 {
		return fmt.Errorf("cors allowMethods is required")
	}

	return nil
}

func (p *Plugin) Config() api.PluginConfig {
	return &CustomConfig{}
}
